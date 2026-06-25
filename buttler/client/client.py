#!/usr/bin/env python3
"""
SmallNet FPGA inference client.

Captures webcam frames, crops/resizes to 28x28 grayscale, converts to
posit<32,2>, and sends to the FPGA inference server via HTTP.  Shows the
processed image alongside the raw webcam feed and displays the predicted
digit with latency and FPS.

Weight upload accepts:
  - TorchScript .pt checkpoint (float32, quantized to posit32 on the fly)
  - Posit-native .dat checkpoint (posit<8,2> with bit-reversal)
"""

import collections
import ctypes
import pathlib
import struct
import threading
import time

import cv2
import gi
import numpy as np
import requests

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GLib, GdkPixbuf, Gtk

# -- MNIST normalization ------------------------------------------------------
MNIST_MEAN = 0.1307
MNIST_STD  = 0.3081

# -- posit<32,2> encoding via stillwater/universal ----------------------------

_lib = ctypes.CDLL(pathlib.Path(__file__).parent / "posit_convert.so")
_lib.float_to_posit32_array.argtypes = [
    ctypes.POINTER(ctypes.c_float),
    ctypes.POINTER(ctypes.c_uint32),
    ctypes.c_size_t,
]
_lib.float_to_posit32_array.restype = None


def float_to_posit32(arr: np.ndarray) -> np.ndarray:
    """Convert float32 array to posit<32,2> uint32 array."""
    flat = np.ascontiguousarray(arr.ravel(), dtype=np.float32)
    out  = np.empty(flat.size, dtype=np.uint32)
    _lib.float_to_posit32_array(
        flat.ctypes.data_as(ctypes.POINTER(ctypes.c_float)),
        out.ctypes.data_as(ctypes.POINTER(ctypes.c_uint32)),
        ctypes.c_size_t(flat.size),
    )
    return out.reshape(arr.shape)


# -- checkpoint loading --------------------------------------------------------

def _bit_reverse8(b: int) -> int:
    return int(f"{b:08b}"[::-1], 2)


_REV8 = np.array([_bit_reverse8(i) for i in range(256)], dtype=np.uint8)


def _read_u64(f) -> int:
    return struct.unpack("<Q", f.read(8))[0]


def _read_vec_u64(f) -> list:
    n = _read_u64(f)
    return list(struct.unpack(f"<{n}Q", f.read(n * 8))) if n else []


def _read_dat_tensor(f) -> np.ndarray:
    """
    Parse one StdTensor<posit<8,2>> from a positnn .dat file.

    write_posit stores posit8 bits reversed (LSB of bitblock -> MSB of byte),
    so we bit-reverse each byte to recover the natural PAWN left-aligned
    encoding (sign at bit 7).
    """
    _m_dim   = _read_u64(f)          # noqa: not needed
    _m_size  = _read_u64(f)
    shape    = _read_vec_u64(f)
    _strides = _read_vec_u64(f)       # noqa
    n        = _read_u64(f)
    raw      = np.frombuffer(f.read(n), dtype=np.uint8)
    natural  = _REV8[raw]             # bit-reverse -> natural posit8 encoding
    # Promote to posit32: put posit8 byte in bits [31:24] (left-aligned)
    return (natural.astype(np.uint32) << 24).reshape(shape)


def load_dat(path: str):
    """
    Load posit<8,2> weights from a positnn .dat checkpoint.
    Returns (fc1_w, fc1_b, fc2_w, fc2_b) as uint32 arrays (posit32-compatible).
    """
    with open(path, "rb") as f:
        nbits = _read_u64(f)
        es    = _read_u64(f)
        if nbits != 8 or es != 2:
            raise ValueError(f"Expected posit<8,2>, got posit<{nbits},{es}>")
        fc1_w = _read_dat_tensor(f)   # [32, 784]
        fc1_b = _read_dat_tensor(f)   # [32]
        fc2_w = _read_dat_tensor(f)   # [10, 32]
        fc2_b = _read_dat_tensor(f)   # [10]
    return fc1_w, fc1_b, fc2_w, fc2_b


def load_pt(path: str, use_float: bool = False):
    """
    Load float32 TorchScript (or state-dict) checkpoint.
    Returns (fc1_w, fc1_b, fc2_w, fc2_b) as posit<32,2> uint32 arrays,
    or as float32 arrays when use_float=True.
    """
    import torch  # optional dependency, only needed for .pt loading

    try:
        model = torch.jit.load(path, map_location="cpu")
        params = [v.detach().float().numpy()
                  for _, v in model.named_parameters()]
    except Exception:
        state = torch.load(path, map_location="cpu")
        if not isinstance(state, dict):
            state = state.state_dict()
        params = [
            state["fc1.weight"].float().numpy(),
            state["fc1.bias"].float().numpy(),
            state["fc2.weight"].float().numpy(),
            state["fc2.bias"].float().numpy(),
        ]

    if use_float:
        return tuple(np.ascontiguousarray(p, dtype=np.float32) for p in params)
    return tuple(float_to_posit32(p) for p in params)


def weights_to_bytes(fc1_w, fc1_b, fc2_w, fc2_b) -> bytes:
    """Concatenate weight arrays into a flat uint32 byte string."""
    return b"".join(a.ravel().tobytes() for a in (fc1_w, fc1_b, fc2_w, fc2_b))


# -- image processing ----------------------------------------------------------

def crop_and_gray(frame_bgr: np.ndarray, invert: bool,
                  zoom: float = 1.0, contrast: float = 1.0) -> np.ndarray:
    """Crop to square, resize to 28x28 grayscale. Returns uint8 [28,28]."""
    h, w = frame_bgr.shape[:2]
    s    = min(h, w)
    # zoom > 1 takes a smaller central region (paper held farther away)
    s_zoomed = max(1, int(s / zoom))
    y0   = (h - s_zoomed) // 2
    x0   = (w - s_zoomed) // 2
    crop = frame_bgr[y0:y0 + s_zoomed, x0:x0 + s_zoomed]
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    small = cv2.resize(gray, (28, 28), interpolation=cv2.INTER_AREA)
    if contrast != 1.0:
        small = np.clip(contrast * (small.astype(np.float32) - 128) + 128, 0, 255).astype(np.uint8)
    if invert:
        small = 255 - small
    return small


def encode_for_infer(small: np.ndarray, use_float: bool = False) -> bytes:
    """Normalize as MNIST and encode 28x28 uint8 to posit<32,2> or float32 bytes."""
    norm = (small.astype(np.float32) / 255.0 - MNIST_MEAN) / MNIST_STD
    if use_float:
        return np.ascontiguousarray(norm.ravel(), dtype=np.float32).tobytes()
    return float_to_posit32(norm.ravel()).tobytes()


# -- numpy array -> GdkPixbuf ---------------------------------------------------

def ndarray_to_pixbuf(arr: np.ndarray) -> GdkPixbuf.Pixbuf:
    """Convert HxWx3 uint8 RGB array to GdkPixbuf."""
    arr = np.ascontiguousarray(arr, dtype=np.uint8)
    h, w = arr.shape[:2]
    return GdkPixbuf.Pixbuf.new_from_data(
        arr.tobytes(),
        GdkPixbuf.Colorspace.RGB,
        False, 8, w, h, w * 3,
    )


# -- GTK application -----------------------------------------------------------

PREVIEW_W = 320
PREVIEW_H = 240
SMALL_SCALE = 8   # 28 x 8 = 224 px for "what model sees"

DIGIT_NAMES = [str(i) for i in range(10)]


class InferenceClient(Gtk.Window):
    def __init__(self):
        super().__init__(title="FPGA Posit Inference")
        self.set_border_width(8)
        self.connect("destroy", Gtk.main_quit)

        self._cap            = None
        self._running        = False
        self._last_lat       = 0.0
        self._latest_frame   = None
        self._frame_ts: collections.deque = collections.deque(maxlen=30)
        self._infer_ts: collections.deque = collections.deque(maxlen=30)
        self._cam_pixbuf     = None
        self._proc_pixbuf    = None
        self._ui_scale       = 1.0
        self._pred_text      = "-"
        self._pred_color     = None

        # Cached widget state — written on GTK thread, read on worker threads
        self._cfg_invert    = False
        self._cfg_use_float = False
        self._cfg_zoom      = 1.0
        self._cfg_contrast  = 1.0
        self._cfg_url       = "http://10.42.0.2:8080"

        self._build_ui()

    # -- UI construction ----------------------------------------------------

    def _build_ui(self):
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.add(root)

        # -- top bar ------------------------------------------------------
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        root.pack_start(bar, False, False, 0)

        bar.pack_start(Gtk.Label(label="Server:"), False, False, 0)
        self._url_entry = Gtk.Entry()
        self._url_entry.set_text("http://10.42.0.2:8080")
        self._url_entry.connect("changed", lambda w: setattr(self, "_cfg_url", w.get_text().rstrip("/")))
        bar.pack_start(self._url_entry, True, True, 0)

        btn_upload = Gtk.Button(label="Upload Weights")
        btn_upload.connect("clicked", self._on_upload_weights)
        bar.pack_start(btn_upload, False, False, 0)

        # -- image area ---------------------------------------------------
        img_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        root.pack_start(img_box, True, True, 0)

        cam_frame = Gtk.Frame(label="Webcam")
        self._cam_da = Gtk.DrawingArea()
        self._cam_da.set_size_request(320, 240)
        self._cam_da.connect("draw", self._on_cam_draw)
        cam_frame.add(self._cam_da)
        img_box.pack_start(cam_frame, True, True, 0)

        # Right column: "What model sees" + big prediction number below
        right_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        img_box.pack_start(right_col, False, False, 0)

        proc_frame = Gtk.Frame(label="What model sees")
        self._proc_da = Gtk.DrawingArea()
        self._proc_da.set_size_request(200, 200)
        self._proc_da.connect("draw", self._on_proc_draw)
        proc_frame.add(self._proc_da)
        right_col.pack_start(proc_frame, True, True, 0)

        pred_frame = Gtk.Frame(label="Prediction")
        self._pred_box = Gtk.Box()
        self._pred_box.set_size_request(200, 200)
        self._pred_lbl = Gtk.Label()
        self._pred_lbl.set_markup("<span font_desc='Monospace Bold 72'>-</span>")
        self._pred_lbl.set_halign(Gtk.Align.CENTER)
        self._pred_lbl.set_valign(Gtk.Align.CENTER)
        self._pred_box.pack_start(self._pred_lbl, True, True, 0)
        pred_frame.add(self._pred_box)
        right_col.pack_start(pred_frame, False, False, 0)

        # -- controls -----------------------------------------------------
        ctrl = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        root.pack_start(ctrl, False, False, 0)

        self._invert_chk = Gtk.CheckButton(label="Invert colors")
        self._invert_chk.connect("toggled", lambda w: setattr(self, "_cfg_invert", w.get_active()))
        ctrl.pack_start(self._invert_chk, False, False, 0)

        self._float_chk = Gtk.CheckButton(label="Send floats")
        self._float_chk.connect("toggled", lambda w: setattr(self, "_cfg_use_float", w.get_active()))
        ctrl.pack_start(self._float_chk, False, False, 0)

        self._start_btn = Gtk.ToggleButton(label="Start")
        self._start_btn.connect("toggled", self._on_start_stop)
        ctrl.pack_end(self._start_btn, False, False, 0)

        # -- sliders ----------------------------------------------------------
        sliders = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        root.pack_start(sliders, False, False, 0)

        sliders.pack_start(Gtk.Label(label="Zoom:"), False, False, 0)
        self._zoom_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, 1.0, 8.0, 0.1)
        self._zoom_scale.set_value(1.0)
        self._zoom_scale.set_digits(1)
        self._zoom_scale.connect("value-changed", lambda w: setattr(self, "_cfg_zoom", w.get_value()))
        sliders.pack_start(self._zoom_scale, True, True, 0)

        sliders.pack_start(Gtk.Label(label="Contrast:"), False, False, 0)
        self._contrast_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, 0.5, 4.0, 0.1)
        self._contrast_scale.set_value(1.0)
        self._contrast_scale.set_digits(1)
        self._contrast_scale.connect("value-changed", lambda w: setattr(self, "_cfg_contrast", w.get_value()))
        sliders.pack_start(self._contrast_scale, True, True, 0)

        # -- stats grid ---------------------------------------------------
        def _stat_row(grid, row, desc, unit, w=7):
            d = Gtk.Label(label=desc)
            d.set_xalign(1.0)
            grid.attach(d, 0, row, 1, 1)
            v = Gtk.Label(label="-")
            v.set_xalign(1.0)
            v.set_width_chars(w)
            grid.attach(v, 1, row, 1, 1)
            u = Gtk.Label(label=unit)
            u.set_xalign(0.0)
            grid.attach(u, 2, row, 1, 1)
            return v

        sg = Gtk.Grid()
        sg.set_column_spacing(6)
        sg.set_row_spacing(2)
        sg.set_margin_start(2)
        root.pack_start(sg, False, False, 0)

        self._v_cam_fps   = _stat_row(sg, 0, "Cam FPS",  "fps")
        self._v_infer_fps = _stat_row(sg, 1, "Infer",    "/s")
        self._v_client    = _stat_row(sg, 2, "Latency",  "ms")
        self._v_hw        = _stat_row(sg, 3, "HW",       "ms")
        self._v_load      = _stat_row(sg, 4, "Load",     "µs")
        self._v_compute   = _stat_row(sg, 5, "Compute",  "µs")
        self._v_read      = _stat_row(sg, 6, "Read",     "µs")

        # -- status line --------------------------------------------------
        self._status_lbl = Gtk.Label(label="No weights loaded.")
        self._status_lbl.set_xalign(0.0)
        self._status_lbl.set_margin_top(2)
        root.pack_start(self._status_lbl, False, False, 0)

        self.connect("key-press-event", self._on_key_press)
        self.show_all()

    # -- draw callbacks (letterbox into DrawingArea) -----------------------

    def _on_cam_draw(self, widget, cr):
        pb = self._cam_pixbuf
        if pb is None:
            return
        aw = widget.get_allocated_width()
        ah = widget.get_allocated_height()
        scale = min(aw / pb.get_width(), ah / pb.get_height())
        sw = int(pb.get_width()  * scale)
        sh = int(pb.get_height() * scale)
        dx = (aw - sw) // 2
        dy = (ah - sh) // 2
        scaled = pb.scale_simple(sw, sh, GdkPixbuf.InterpType.BILINEAR)
        Gdk.cairo_set_source_pixbuf(cr, scaled, dx, dy)
        cr.paint()

    def _on_proc_draw(self, widget, cr):
        pb = self._proc_pixbuf
        if pb is None:
            return
        s = min(widget.get_allocated_width(), widget.get_allocated_height())
        scaled = pb.scale_simple(s, s, GdkPixbuf.InterpType.NEAREST)
        dx = (widget.get_allocated_width()  - s) // 2
        dy = (widget.get_allocated_height() - s) // 2
        Gdk.cairo_set_source_pixbuf(cr, scaled, dx, dy)
        cr.paint()

    # -- weight upload ------------------------------------------------------

    def _on_upload_weights(self, _btn):
        dialog = Gtk.FileChooserDialog(
            title="Select checkpoint",
            parent=self,
            action=Gtk.FileChooserAction.OPEN,
        )
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OPEN,   Gtk.ResponseType.OK)

        ff = Gtk.FileFilter()
        ff.set_name("Checkpoints (*.pt, *.dat)")
        ff.add_pattern("*.pt")
        ff.add_pattern("*.dat")
        dialog.add_filter(ff)

        resp = dialog.run()
        path = dialog.get_filename()
        dialog.destroy()
        if resp != Gtk.ResponseType.OK or not path:
            return

        self._status_lbl.set_text("Converting...")
        threading.Thread(target=self._upload_worker,
                         args=(path, self._cfg_url, self._cfg_use_float),
                         daemon=True).start()

    def _upload_worker(self, path: str, url: str, use_float: bool = False):
        try:
            if path.endswith(".dat"):
                if use_float:
                    GLib.idle_add(self._status_lbl.set_text,
                                  "Error: float mode not supported for .dat checkpoints")
                    return
                weights = load_dat(path)
            else:
                weights = load_pt(path, use_float=use_float)
            body = weights_to_bytes(*weights)
            GLib.idle_add(self._status_lbl.set_text, "Uploading...")
            r = requests.post(f"{url}/weights", data=body, timeout=30)
            r.raise_for_status()
            GLib.idle_add(self._status_lbl.set_text, "Weights loaded.")
        except Exception as e:
            GLib.idle_add(self._status_lbl.set_text, f"Error: {e}")

    # -- start / stop -------------------------------------------------------

    def _on_start_stop(self, btn):
        if btn.get_active():
            self._cap = cv2.VideoCapture(0)
            if not self._cap.isOpened():
                btn.set_active(False)
                self._status_lbl.set_text("Cannot open webcam.")
                return
            self._cap.set(cv2.CAP_PROP_FPS, 60)
            self._running = True
            btn.set_label("Stop")
            threading.Thread(target=self._capture_loop, daemon=True).start()
            threading.Thread(target=self._infer_loop,   daemon=True).start()
        else:
            self._running = False
            btn.set_label("Start")
            # Threads check _running and exit; cap released by capture thread

    # -- capture thread -----------------------------------------------------

    def _capture_loop(self):
        cap = self._cap
        while self._running:
            ret, frame = cap.read()
            if not ret:
                continue

            now = time.monotonic()
            self._frame_ts.append(now)

            preview_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            cam_pb = ndarray_to_pixbuf(preview_rgb)

            small = crop_and_gray(frame,
                                  self._cfg_invert,
                                  self._cfg_zoom,
                                  self._cfg_contrast)
            proc_pb = ndarray_to_pixbuf(cv2.cvtColor(small, cv2.COLOR_GRAY2RGB))

            self._latest_frame = frame  # atomic enough for our use

            GLib.idle_add(self._apply_cam_frame, cam_pb, proc_pb,
                          self._compute_frame_fps())

        cap.release()
        self._cap = None

    def _apply_cam_frame(self, cam_pb, proc_pb, fps: float):
        self._cam_pixbuf  = cam_pb
        self._proc_pixbuf = proc_pb
        self._cam_da.queue_draw()
        self._proc_da.queue_draw()
        self._v_cam_fps.set_text(f"{fps:.1f}")
        return False  # don't repeat

    def _set_pred(self, text: str, color: str | None = None):
        self._pred_text  = text
        self._pred_color = color
        size = int(72 * self._ui_scale)
        col  = f" foreground='{color}'" if color else ""
        self._pred_lbl.set_markup(
            f"<span font_desc='Monospace Bold {size}'{col}>{text}</span>"
        )

    def _apply_scale(self, scale: float):
        self._ui_scale = scale
        sz_cam  = (int(320 * scale), int(240 * scale))
        sz_proc = int(200 * scale)
        self._cam_da.set_size_request(*sz_cam)
        self._proc_da.set_size_request(sz_proc, sz_proc)
        self._pred_box.set_size_request(sz_proc, sz_proc)
        self._set_pred(self._pred_text, self._pred_color)
        self.resize(1, 1)

    def _on_key_press(self, _widget, event):
        if not (event.state & Gdk.ModifierType.CONTROL_MASK):
            return False
        if event.keyval in (Gdk.KEY_plus, Gdk.KEY_equal, Gdk.KEY_KP_Add):
            self._apply_scale(min(3.0, round(self._ui_scale + 0.25, 2)))
            return True
        if event.keyval in (Gdk.KEY_minus, Gdk.KEY_KP_Subtract):
            self._apply_scale(max(0.5, round(self._ui_scale - 0.25, 2)))
            return True
        if event.keyval in (Gdk.KEY_0, Gdk.KEY_KP_0):
            self._apply_scale(1.0)
            return True
        return False

    def _compute_frame_fps(self) -> float:
        ts = self._frame_ts
        if len(ts) < 2:
            return 0.0
        return (len(ts) - 1) / (ts[-1] - ts[0])

    def _compute_infer_fps(self) -> float:
        ts = self._infer_ts
        if len(ts) < 2:
            return 0.0
        return (len(ts) - 1) / (ts[-1] - ts[0])

    # -- inference thread ---------------------------------------------------

    def _infer_loop(self):
        while self._running:
            frame = self._latest_frame
            if frame is None:
                time.sleep(0.001)
                continue
            url       = self._cfg_url
            use_float = self._cfg_use_float
            try:
                body = encode_for_infer(
                    crop_and_gray(frame, self._cfg_invert,
                                  self._cfg_zoom, self._cfg_contrast),
                    use_float,
                )
                t0 = time.monotonic()
                r  = requests.post(f"{url}/infer", data=body, timeout=5)
                lat_ms = (time.monotonic() - t0) * 1000
                r.raise_for_status()
                data       = r.json()
                cls        = data["class"]
                time_us    = data.get("time_us",    0)
                load_us    = data.get("load_us",    0)
                compute_us = data.get("compute_us", 0)
                read_us    = data.get("read_us",    0)
                GLib.idle_add(self._update_prediction,
                              cls, lat_ms, time_us, load_us, compute_us, read_us)
            except Exception as e:
                GLib.idle_add(self._update_prediction_error, str(e))

    def _update_prediction(self, cls: int, lat_ms: float,
                           time_us: int, load_us: int,
                           compute_us: int, read_us: int):
        self._infer_ts.append(time.monotonic())
        self._last_lat = lat_ms
        name = DIGIT_NAMES[cls] if 0 <= cls < len(DIGIT_NAMES) else str(cls)
        self._set_pred(name)
        self._v_infer_fps.set_text(f"{self._compute_infer_fps():.1f}")
        self._v_client.set_text(f"{lat_ms:.0f}")
        self._v_hw.set_text(f"{time_us / 1000:.1f}")
        self._v_load.set_text(str(load_us))
        self._v_compute.set_text(str(compute_us))
        self._v_read.set_text(str(read_us))
        self._status_lbl.set_text("Weights loaded.")
        return False

    def _update_prediction_error(self, msg: str):
        self._set_pred("!", color="red")
        self._status_lbl.set_text(f"Error: {msg[:120]}")
        return False


# -- entry point ---------------------------------------------------------------

if __name__ == "__main__":
    app = InferenceClient()
    Gtk.main()
