print("Hello from Python program!")

import os
from time import sleep

import _imp

_imp.extension_suffixes()

print("HELLO!")


import binascii
import bz2

original_data = "This is the original text.".encode("utf8")
print("Original     :", len(original_data), original_data)

compressed = bz2.compress(original_data)
print("Compressed   :", len(compressed), binascii.hexlify(compressed))

decompressed = bz2.decompress(compressed)
print("Decompressed :", len(decompressed), decompressed)

result_filename = os.getenv("RESULT_FILENAME")
result_value = os.getenv("RESULT_VALUE")
r = ""


def test_lru():
    from lru import LRU

    l = LRU(5)  # Create an LRU container that can hold 5 items

    print(l.peek_first_item(), l.peek_last_item())  # return the MRU key and LRU key
    # Would print None None

    for i in range(5):
        l[i] = str(i)
    print(l.items())  # Prints items in MRU order
    # Would print [(4, '4'), (3, '3'), (2, '2'), (1, '1'), (0, '0')]

    print(l.peek_first_item(), l.peek_last_item())  # return the MRU key and LRU key
    # Would print (4, '4') (0, '0')

    l[5] = "5"  # Inserting one more item should evict the old item
    print(l.items())


test_lru()

# result_value = str(_imp.extension_suffixes())
# result_value = decompressed.decode("utf8")

if not result_filename:
    print("RESULT_FILENAME is not set")
    exit(1)

if result_value:
    r = result_value
else:
    r = "RESULT_VALUE is not set"

with open(result_filename, "w") as f:
    f.write(r)
