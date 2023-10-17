print("Hello from Python program!")

import os
from time import sleep

result_filename = os.getenv("RESULT_FILENAME")
result_value = os.getenv("RESULT_VALUE")
r = ""

if not result_filename:
    print("RESULT_FILENAME is not set")
    exit(1)

if result_value:
    r = result_value
else:
    r = "RESULT_VALUE is not set"

with open(result_filename, "w") as f:
    f.write(r)
