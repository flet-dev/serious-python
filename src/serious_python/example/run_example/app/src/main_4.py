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


# Schedule this inside the event loop thread
def thread_main():
    print("thread_main")
    dart_bridge.send_bytes(b"_start_loop_in_thread!")
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.create_task(async_counter())
    print("[Python] background_task started, loop running.")
    loop.run_forever()


threading.Thread(target=thread_main, daemon=True).start()

import atexit

atexit.register(lambda: print(b"Python interpreter shutting down!"))

dart_bridge.send_bytes(b"python script completed - 3")

import threading

threading.Event().wait()
