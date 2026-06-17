import krpc
from buttons import Buttons
from lcd import LCD
from time import sleep

if __name__ == '__main__':
    conn = krpc.connect('PYNQ Z2 Client', '192.168.137.1')
    vessel = conn.space_center.active_vessel

    buttons = Buttons()
    lcd = LCD()

    while True:
        yaw = 0
        pitch = 0
        throttle = 0

        # Udate yaw
        if buttons.left:
            yaw = -1
        elif buttons.right:
            yaw = 1

        # Update pitch
        if buttons.up:
            pitch = 1
        elif buttons.down:
            pitch = -1

        # Update throttle
        if buttons.select:
            throttle = 1

        vessel.control.yaw = yaw
        vessel.control.pitch = pitch
        vessel.control.throttle = throttle

        print(f'Yaw: {int(yaw):+1d}, Pitch: {int(pitch):+1d}, Throttle: {int(throttle):+1d}')

        lcd[0] = f'Y:{int(yaw):+1d} P:{int(pitch):+1d}'
        lcd[1] = f'T:{int(throttle):+1d}'