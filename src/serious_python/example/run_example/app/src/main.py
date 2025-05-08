import asyncio
import os

import dart_bridge

loop = None
message_queue = None

DART_PORT = int(os.getenv("DART_PORT", "0"))


def enqueue_from_dart(data: bytes):
    if loop and message_queue:
        loop.call_soon_threadsafe(message_queue.put_nowait, data)
    else:
        print("⚠️ Loop or queue not ready")


async def receive_loop():
    global loop, message_queue

    print("🔁 Entering receive loop...")
    loop = asyncio.get_running_loop()  # ✅ Safe! This is inside asyncio.run
    message_queue = asyncio.Queue()

    dart_bridge.set_enqueue_handler_func(enqueue_from_dart)
    print("✅ Python registered enqueue handler")
    dart_bridge.send_bytes(DART_PORT, b"Python ready to receive messages!")

    try:
        while True:
            msg = await message_queue.get()
            if msg == b"$shutdown":
                print("👋 Shutdown message received")
                break
            print("[Python] Received:", msg)
            dart_bridge.send_bytes(DART_PORT, b"Echo: " + msg)
    except asyncio.CancelledError:
        print("⚠️ receive_loop() cancelled")
    except Exception as e:
        print("❌ Exception in receive_loop():", e)
    finally:
        print("👋 Exiting receive_loop")


# Top-level wrapper
async def main():
    try:
        await receive_loop()
    except KeyboardInterrupt:
        print("🛑 KeyboardInterrupt — exiting cleanly")


asyncio.run(main())
