import asyncio
import threading
import time

import dart_bridge


class DartHost:
    def __init__(self):
        self.loop = asyncio.new_event_loop()
        self.queue = None
        self.ready = False
        self._start_loop_in_thread()

    def _start_loop_in_thread(self):
        def thread_main():
            dart_bridge.send_bytes(b"_start_loop_in_thread!")
            # asyncio.set_event_loop(self.loop)
            self.queue = asyncio.Queue()
            self.loop.create_task(self._background_task())
            self.ready = True  # ✅ Set this only after queue & task are created
            print("[Python] background_task started, loop running.")
            self.loop.run_forever()

        print("[Python] Starting event loop thread...")
        threading.Thread(target=thread_main, daemon=True).start()

    async def _background_task(self):
        print("[Python] Entering background_task loop.")
        dart_bridge.send_bytes(b"_background_task!")
        i = 0
        while True:
            dart_bridge.send_bytes(str(i).encode())
            await asyncio.sleep(1)
            i += 1

    def enqueue_message(self, data: bytes):
        print(f"[Python] enqueue_message called with !!!: {data}")
        pass


# Global instance
host = DartHost()


def enqueue_message(data: bytes):
    host.enqueue_message(data)


dart_bridge.send_bytes(b"python script finished!")


async def async_counter():
    i = 0
    while True:
        dart_bridge.send_bytes(f"from thread: {i}".encode())
        await asyncio.sleep(1)
        i += 1


# Schedule this inside the event loop thread
def _start_loop_in_thread(self):
    def thread_main():
        dart_bridge.send_bytes(b"_start_loop_in_thread!")
        asyncio.set_event_loop(self.loop)
        self.queue = asyncio.Queue()
        self.loop.create_task(self._background_task())
        self.loop.create_task(async_counter())  # ✅ <- here
        self.ready = True
        print("[Python] background_task started, loop running.")
        self.loop.run_forever()
