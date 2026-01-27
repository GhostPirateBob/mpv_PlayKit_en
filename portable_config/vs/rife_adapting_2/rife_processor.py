"""
rife_processor.py - Optimized RIFE pipeline
"""

import os
import fractions
import vapoursynth as vs
from k7sfunc._external import vsmlrt

core = vs.core

def get_matrix_name(prop_val):
    """Map VS/mpv matrix integers to resize string names."""
    mapping = {
        1: "709",       # BT.709 (HD)
        2: "709",       # Unspecified - default to 709
        4: "fcc",       # FCC
        5: "470bg",     # BT.470BG (PAL)
        6: "170m",      # SMPTE 170M (NTSC)
        7: "240m",      # SMPTE 240M
        9: "2020ncl",   # BT.2020 NCL (HDR)
        10: "2020cl",   # BT.2020 CL
    }
    return mapping.get(prop_val, "709")

def process(
    clip: vs.VideoNode,
    crop_l: int,
    crop_t: int,
    crop_w: int,
    crop_h: int,
    target_w: int,
    target_h: int,
    model: int,
    gpu_id: int,
    gpu_t: int,
    padding_enabled: bool = False,
    padding_orig_w: int = 0,
    padding_orig_h: int = 0,
    multiplier: int = 2,
    # Config from template
    model_dir: str = "rife_v2",
    model_map: str = "{}",
    ensemble: bool = False,
    implementation: int = 2,
    trt_int8: bool = False,
    trt_fp16: bool = True,
    trt_workspace: int = 256,
    trt_cuda_graph: bool = True,
    trt_cublas: bool = True,
    trt_cudnn: bool = True,
    trt_static_shape: bool = True,
) -> vs.VideoNode:

    # Validate multiplier parameter
    if multiplier not in (2, 3):
        raise vs.Error(f"Invalid multiplier: {multiplier}. Must be 2 or 3")

    # Log function entry
    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_INIT] Starting RIFE processing: "
        f"clip={clip.width}x{clip.height}, "
        f"crop=({crop_l},{crop_t},{crop_w},{crop_h}), "
        f"target={target_w}x{target_h}, model={model}, gpu={gpu_id}, "
        f"threads={gpu_t}, multiplier={multiplier}")

    # 1. Apply Crop
    # We do this first so we don't process pixels we are about to throw away
    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_CROP] Input clip: {clip.width}x{clip.height}")

    if crop_w > 0 and crop_h > 0:
        if crop_w != clip.width or crop_h != clip.height:
            right_crop = clip.width - crop_w - crop_l
            bottom_crop = clip.height - crop_h - crop_t
            core.log_message(vs.MESSAGE_TYPE_DEBUG,
                f"[rife_adaptive][PY_CROP] Applying crop: left={crop_l}, top={crop_t}, "
                f"right={right_crop}, bottom={bottom_crop}")
            clip = core.std.CropRel(clip, left=crop_l, top=crop_t, right=right_crop, bottom=bottom_crop)
            core.log_message(vs.MESSAGE_TYPE_DEBUG,
                f"[rife_adaptive][PY_CROP] After crop: {clip.width}x{clip.height}")
        else:
            core.log_message(vs.MESSAGE_TYPE_DEBUG,
                f"[rife_adaptive][PY_CROP] No crop needed (crop dimensions match input)")
    else:
        core.log_message(vs.MESSAGE_TYPE_DEBUG,
            f"[rife_adaptive][PY_CROP] No crop specified (crop_w={crop_w}, crop_h={crop_h})")

    # 2. Handle Padding or Resize
    if padding_enabled:
        # Padding path: add black borders, process at padded size, crop back after RIFE
        pad_right = target_w - clip.width
        pad_bottom = target_h - clip.height

        core.log_message(vs.MESSAGE_TYPE_DEBUG,
            f"[rife_adaptive][PY_PAD] Padding: right={pad_right}, bottom={pad_bottom}")

        if pad_right > 0 or pad_bottom > 0:
            clip = core.std.AddBorders(clip, left=0, right=pad_right, top=0, bottom=pad_bottom)
            core.log_message(vs.MESSAGE_TYPE_DEBUG,
                f"[rife_adaptive][PY_PAD] After padding: {clip.width}x{clip.height}")

    # 3. Prepare for AI (Format Convert, optionally Resize)
    # RIFE requires RGB input (RGBH is best for TensorRT FP16)

    # Detect Color Matrix (Keep 709 as safe default)
    matrix_val = clip.get_frame(0).props.get("_Matrix", 1)
    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_MATRIX] Frame _Matrix property: {matrix_val}")

    matrix_str = get_matrix_name(matrix_val)
    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_MATRIX] Mapped to resize matrix: '{matrix_str}'")

    if padding_enabled:
        # Padding path: only convert format, no resize (already at target size from padding)
        core.log_message(vs.MESSAGE_TYPE_DEBUG,
            f"[rife_adaptive][PY_CONVERT] Format only: {clip.width}x{clip.height} -> RGBH (matrix={matrix_str})")

        clip_rgb = core.resize.Spline36(
            clip,
            format=vs.RGBH,
            matrix_in_s=matrix_str
        )
    else:
        # Downscale path: resize and convert in one step
        dest_w = target_w if target_w > 0 else clip.width
        dest_h = target_h if target_h > 0 else clip.height

        core.log_message(vs.MESSAGE_TYPE_DEBUG,
            f"[rife_adaptive][PY_RESIZE] Single-pass Spline36: "
            f"{clip.width}x{clip.height} {clip.format.name} -> {dest_w}x{dest_h} RGBH (matrix={matrix_str})")

        clip_rgb = core.resize.Spline36(
            clip,
            width=dest_w,
            height=dest_h,
            format=vs.RGBH,
            matrix_in_s=matrix_str
        )

    # 3. Model Path Logic
    plg_dir = os.path.dirname(core.trt.Version()["path"]).decode()
    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_MODEL] Plugin directory: {plg_dir}")

    # Parse model_map - may be dict (from template) or JSON string
    import json
    if isinstance(model_map, dict):
        model_mapping = model_map
    elif model_map:
        try:
            model_mapping = json.loads(model_map)
        except json.JSONDecodeError:
            model_mapping = {}
    else:
        model_mapping = {}

    mdl_pname = model_dir + "/"
    mdl_fname = model_mapping.get(str(model), model_mapping.get(model, "rife_v4.15"))
    if not mdl_fname or mdl_fname == "rife_v4.15":
        # Fallback to default mapping if model_map doesn't have this model
        mdl_fname = {
            4151: "rife_v4.15_lite",
            4221: "rife_v4.22_lite",
        }.get(model, "rife_v4.15")
    mdl_pth = plg_dir + "/models/" + mdl_pname + mdl_fname + ".onnx"

    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_MODEL] Model path: {mdl_pth}")
    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_MODEL] Model exists: {os.path.exists(mdl_pth)}")

    if not os.path.exists(mdl_pth):
        core.log_message(vs.MESSAGE_TYPE_ERROR,
            f"[rife_adaptive][PY_MODEL] Model NOT FOUND: {mdl_pth}")
        raise vs.Error(f"RIFE model not found: {mdl_pth}")

    # 4. RIFE Execution
    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_RIFE] Executing with: "
        f"multiplier={multiplier}x, "
        f"model={model}, ensemble={ensemble}, gpu_threads={gpu_t}, "
        f"backend=TRT(fp16={trt_fp16}, static_shape={trt_static_shape}, device={gpu_id})")

    clip_rife = vsmlrt.RIFE(
        clip=clip_rgb,
        multi=fractions.Fraction(multiplier, 1),
        scale=1,
        model=model,
        ensemble=ensemble,
        _implementation=implementation,
        video_player=True,
        backend=vsmlrt.BackendV2.TRT(
            num_streams=gpu_t,
            int8=trt_int8,
            fp16=trt_fp16,
            output_format=1,
            workspace=trt_workspace,
            use_cuda_graph=trt_cuda_graph,
            use_cublas=trt_cublas,
            use_cudnn=trt_cudnn,
            static_shape=trt_static_shape,
            min_shapes=[0, 0],
            opt_shapes=None,
            max_shapes=None,
            device_id=gpu_id,
            short_path=True
        )
    )

    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_RIFE] RIFE execution configured successfully")

    # 5. Crop back if padding was used
    if padding_enabled and (padding_orig_w > 0 and padding_orig_h > 0):
        crop_right = clip_rife.width - padding_orig_w
        crop_bottom = clip_rife.height - padding_orig_h

        core.log_message(vs.MESSAGE_TYPE_DEBUG,
            f"[rife_adaptive][PY_CROP_BACK] Removing padding: right={crop_right}, bottom={crop_bottom}")

        if crop_right > 0 or crop_bottom > 0:
            clip_rife = core.std.Crop(clip_rife, left=0, right=crop_right, top=0, bottom=crop_bottom)
            core.log_message(vs.MESSAGE_TYPE_DEBUG,
                f"[rife_adaptive][PY_CROP_BACK] After crop: {clip_rife.width}x{clip_rife.height}")

    # 6. Output Conversion (RGBH -> YUV420P10)
    # We must convert back to YUV for MPV/Display:
    # Nvidia VSR requires YUV (NV12/P010) input and solves banding
    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_OUTPUT] Converting RGBH -> YUV420P10 (matrix={matrix_str})")

    clip_out = core.resize.Spline36(
        clip=clip_rife,
        format=vs.YUV420P10,
        matrix_s=matrix_str
    )

    core.log_message(vs.MESSAGE_TYPE_DEBUG,
        f"[rife_adaptive][PY_OUTPUT] Final output: {clip_out.width}x{clip_out.height} {clip_out.format.name}")

    return clip_out
