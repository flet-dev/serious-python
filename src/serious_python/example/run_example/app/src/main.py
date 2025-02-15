print("Hello from Python program!")

import os
import sys
import traceback
from pathlib import Path
from time import sleep

import _imp

_imp.extension_suffixes()

print("HELLO!")
print("sys.path:", sys.path)

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
    return ""


def test_numpy_basic():
    try:
        print("Testing NUMPY!")
        from numpy import array

        assert (array([1, 2]) + array([3, 5])).tolist() == [4, 7]
        return "numpy basic test - OK"
    except Exception as e:
        return f"numpy: test_basic - error: {traceback.format_exc()}"


def test_numpy_performance():
    print("calling test_numpy_performance()")
    from time import time

    import numpy as np

    start_time = time()
    SIZE = 500
    a = np.random.rand(SIZE, SIZE)
    b = np.random.rand(SIZE, SIZE)
    np.dot(a, b)

    # With OpenBLAS, the test devices take at most 0.4 seconds. Without OpenBLAS, they take
    # at least 1.0 seconds.
    duration = time() - start_time
    print(f"{duration:.3f}")
    assert duration < 0.7


if not result_filename:
    print("RESULT_FILENAME is not set")
    exit(1)

r = ""
if result_value:
    r = result_value
else:
    r = "RESULT_VALUE is not set"


def test_sqlite():
    try:
        # import ctypes

        # ctypes.cdll.LoadLibrary("libsqlite3_python.so")
        import sqlite3

        out_dir = Path(result_filename).parent
        conn = sqlite3.connect(str(out_dir.joinpath("mydb.db")))

        conn.execute(
            """CREATE TABLE COMPANY
                (ID INT PRIMARY KEY     NOT NULL,
                NAME           TEXT    NOT NULL,
                AGE            INT     NOT NULL,
                ADDRESS        CHAR(50),
                SALARY         REAL);"""
        )

        conn.execute(
            "INSERT INTO COMPANY (ID,NAME,AGE,ADDRESS,SALARY) \
            VALUES (1, 'Paul', 32, 'California', 20000.00 )"
        )

        conn.execute(
            "INSERT INTO COMPANY (ID,NAME,AGE,ADDRESS,SALARY) \
            VALUES (2, 'Allen', 25, 'Texas', 15000.00 )"
        )

        conn.execute(
            "INSERT INTO COMPANY (ID,NAME,AGE,ADDRESS,SALARY) \
            VALUES (3, 'Teddy', 23, 'Norway', 20000.00 )"
        )

        conn.execute(
            "INSERT INTO COMPANY (ID,NAME,AGE,ADDRESS,SALARY) \
            VALUES (4, 'Mark', 25, 'Rich-Mond ', 65000.00 )"
        )

        conn.commit()
        print("Records created successfully")

        conn.close()

        return "\nsqlite: test_basic - OK"
    except Exception as e:
        return f"\nsqlite: test_basic - error: {e}"


def test_pyjnius():
    from time import sleep

    from jnius import autoclass

    activity = autoclass(os.getenv("MAIN_ACTIVITY_HOST_CLASS_NAME")).mActivity
    Secure = autoclass("android.provider.Settings$Secure")

    version = autoclass("android.os.Build$VERSION")
    os_build = autoclass("android.os.Build")
    base_os = version.BASE_OS

    DisplayMetrics = autoclass("android.util.DisplayMetrics")
    metrics = DisplayMetrics()

    return (
        str(activity.getClass().getName())
        + " os: "
        + str(os_build)
        + " FLET_JNI_READY: "
        + str(os.getenv("FLET_JNI_READY"))
        + " DPI: "
        + str(metrics.getDeviceDensity())
    )


r += test_sqlite()
# r += test_pyjnius()
# r += test_lru()
r += test_numpy_basic()
test_numpy_performance()

# result_value = str(_imp.extension_suffixes())
# result_value = decompressed.decode("utf8")

with open(result_filename, "w") as f:
    f.write(r)
