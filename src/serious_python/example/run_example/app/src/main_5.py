import asyncio
import threading

import dart_bridge

message_queue = asyncio.Queue()
dart_bridge.set_enqueue_handler_func(message_queue.put_nowait)


async def receive_loop():
    print("Entering receive_loop()")
    while True:
        msg = await message_queue.get()
        print("[Python] Received from Dart:", msg)
        dart_bridge.send_bytes(f"ECHO: {msg.decode()}".encode())


dart_bridge.send_bytes(b"python script completed - 11!!")

# asyncio.run(receive_loop())


# Schedule this inside the event loop thread
def thread_main():
    print("thread_main")
    dart_bridge.send_bytes(b"_start_loop_in_thread!")
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.create_task(receive_loop())
    print("[Python] background_task started, loop running.")
    loop.run_forever()


threading.Thread(target=thread_main, daemon=True).start()

import atexit

atexit.register(lambda: print(b"Python interpreter shutting down!"))

dart_bridge.send_bytes(b"python script completed - 3")

import threading

threading.Event().wait()
