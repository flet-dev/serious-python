import os

from flask import Flask, request

print("Python program has started!")

# for name, value in os.environ.items():
#     print("{0}: {1}".format(name, value))

app = Flask(__name__)


@app.route("/")
def hello_world():
    return "Hello from Flask, World!"


@app.route("/python", methods=["POST"])
def run_python():
    print(request.json)
    return "result!"


app.run(port=8000)
