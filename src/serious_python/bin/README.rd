pip commands:

```
python -m pip install --upgrade --target 2 --no-index --find-links file:///path/to/index.html micropip --verbose
```

`index.html` example:

```html
<a href="https://cdn.jsdelivr.net/pyodide/v0.24.1/full/micropip-0.5.0-py3-none-any.whl">micropip-0.5.0-py3-none-any.whl</a>
<a href="https://cdn.jsdelivr.net/pyodide/v0.24.1/full/packaging-23.1-py3-none-any.whl">packaging-23.1-py3-none-any.whl</a>
<a href="https://cdn.jsdelivr.net/pyodide/v0.24.1/full/numpy-1.25.2-cp311-cp311-emscripten_3_1_45_wasm32.whl">numpy-1.25.2-cp311-cp311-emscripten_3_1_45_wasm32.whl</a>
```