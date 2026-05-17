#!/usr/bin/env python3
"""
Native UVC PTZ control for Insta360 Link 2.
No drivers needed — uses standard UVC protocol over USB.
"""
import usb.core
import usb.util
import time

# UVC PTZ control constants
# Insta360 Link 2 VID:PID = 0x2E1A:0x4C04
VID = 0x2E1A
PID = 0x4C04

# UVC standard control codes
UVC_REQUEST = 0x01
PAN_CONTROL = 0x09
TILT_CONTROL = 0x0A
ZOOM_CONTROL = 0x0B

def find_camera():
    """Find Insta360 Link 2 via USB."""
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        # Try any UVC camera
        for vid, pid in [(0x2E1A, 0x4C04), (0x046D, 0x085C)]:
            dev = usb.core.find(idVendor=vid, idProduct=pid)
            if dev:
                break
    return dev

def set_ptz(dev, pan: int, tilt: int, zoom: int = 100):
    """Set absolute pan/tilt/zoom.
    Pan:  -3600 (left) to 3600 (right), 0 = center
    Tilt: -3600 (down) to 3600 (up), 0 = center
    Zoom: 100 (1x) to 400 (4x)
    """
    try:
        # Detach kernel driver if active
        for cfg in dev:
            for intf in cfg:
                if dev.is_kernel_driver_active(intf.bInterfaceNumber):
                    dev.detach_kernel_driver(intf.bInterfaceNumber)

        dev.set_configuration()

        def send_control(control, value):
            """Send a UVC control request."""
            data = value.to_bytes(4, byteorder='little', signed=True)
            dev.ctrl_transfer(
                0x21,  # bmRequestType: host-to-device, class, interface
                0x01,  # SET_CUR
                control << 8,  # wValue
                0x0100,        # wIndex: interface 1, entity 0
                data
            )

        send_control(PAN_CONTROL, pan)
        send_control(TILT_CONTROL, tilt)
        send_control(ZOOM_CONTROL, zoom)
        return True
    except Exception as e:
        return str(e)

def pan_left():
    dev = find_camera()
    if dev:
        return set_ptz(dev, -1800, 0, 100)
    return "Camera not found"

def pan_right():
    dev = find_camera()
    if dev:
        return set_ptz(dev, 1800, 0, 100)
    return "Camera not found"

def pan_center():
    dev = find_camera()
    if dev:
        return set_ptz(dev, 0, 0, 100)
    return "Camera not found"

def tilt_up():
    dev = find_camera()
    if dev:
        return set_ptz(dev, 0, 900, 100)
    return "Camera not found"

def tilt_down():
    dev = find_camera()
    if dev:
        return set_ptz(dev, 0, -900, 100)
    return "Camera not found"

def scan_room():
    """Pan left to right, detecting as we go."""
    dev = find_camera()
    if not dev:
        print("Camera not found via USB.")
        return

    positions = [
        (-2400, 0, "far left"),
        (-1200, 0, "left"),
        (0, 0, "center"),
        (1200, 0, "right"),
        (2400, 0, "far right"),
    ]

    import cv2
    cap = cv2.VideoCapture(0)

    for pan, tilt, label in positions:
        r = set_ptz(dev, pan, tilt, 100)
        time.sleep(1.5)  # let camera settle

        ret, frame = cap.read()
        if ret:
            # Run YOLO on this frame
            from ultralytics import YOLO
            model = YOLO("yolov8n.pt")
            results = model(frame, verbose=False)
            objects = []
            for r in results:
                for box in r.boxes:
                    objects.append(r.names[int(box.cls[0])])
            unique = list(set(objects))
            print(f"  {label}: {unique or 'nothing detected'} ({len(objects)} total)")
        else:
            print(f"  {label}: capture failed")

    cap.release()
    set_ptz(dev, 0, 0, 100)  # back to center
    print("Scan complete.")

if __name__ == "__main__":
    import sys
    cmd = sys.argv[1] if len(sys.argv) > 1 else "scan"

    if cmd == "left":
        print(pan_left())
    elif cmd == "right":
        print(pan_right())
    elif cmd == "center":
        print(pan_center())
    elif cmd == "tilt_up":
        print(tilt_up())
    elif cmd == "tilt_down":
        print(tilt_down())
    elif cmd == "scan":
        scan_room()
    else:
        print(f"Commands: left, right, center, tilt_up, tilt_down, scan")
