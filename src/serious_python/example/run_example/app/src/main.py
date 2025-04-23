import asyncio

import dart_bridge

loop = None
message_queue = None


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
    dart_bridge.send_bytes(b"Python ready to receive messages!")

    while True:
        msg = await message_queue.get()
        print("[Python] Received from Dart:", msg)
        dart_bridge.send_bytes(f"ECHO: {msg.decode()}".encode())
        message_queue.task_done()


asyncio.run(receive_loop())
