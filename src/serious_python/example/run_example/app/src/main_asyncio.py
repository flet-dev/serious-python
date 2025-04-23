import asyncio
import threading

import dart_bridge


def enqueue_message(data: bytes):
    print("Enqueue message:", data)


async def async_counter():
    i = 0
    while True:
        dart_bridge.send_bytes(f"from thread: {i}".encode())
        await asyncio.sleep(1)
        i += 1


dart_bridge.send_bytes(b"python script completed - 3!!")

asyncio.run(async_counter())
