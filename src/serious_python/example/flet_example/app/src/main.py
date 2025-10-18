import logging
import os
import sys
import urllib.request

import flet as ft
from flet.version import version

# logging.basicConfig(level=logging.DEBUG)

print("Hello from Python!")
print(__name__)

# import aaa
app_data = os.environ["FLET_APP_DATA"]
app_temp = os.environ["FLET_APP_TEMP"]


def main(page: ft.Page):
    page.title = "Flet counter example"
    page.vertical_alignment = ft.MainAxisAlignment.CENTER

    txt_number = ft.TextField(value="0", text_align=ft.TextAlign.RIGHT, width=100)

    def minus_click(e):
        print("Clicked minus button")
        txt_number.value = str(int(txt_number.value) - 1)
        page.update()

    def plus_click(e):
        txt_number.value = str(int(txt_number.value) + 1)
        page.update()

    def check_ssl(e):
        try:
            with urllib.request.urlopen("https://google.com") as res:
                result = "OK"
        except Exception as ex:
            result = str(ex)
        page.show_dialog(ft.AlertDialog(content=ft.Text(result)))
        # print(result)

    page.add(
        ft.Row(
            [
                ft.IconButton(
                    ft.Icons.REMOVE, key="test:decrement", on_click=minus_click
                ),
                txt_number,
                ft.IconButton(ft.Icons.ADD, key="test:increment", on_click=plus_click),
            ],
            alignment=ft.MainAxisAlignment.CENTER,
            expand=True,
        ),
        ft.Row(
            [
                ft.Text(f"Flet version: {version}"),
                ft.OutlinedButton("Check SSL", on_click=check_ssl),
                ft.OutlinedButton("Exit app", on_click=lambda _: sys.exit(100)),
            ],
            wrap=True,
            alignment=ft.MainAxisAlignment.CENTER,
        ),
        ft.Text(f"App data dir: {app_data}"),
        ft.Text(f"App temp dir: {app_temp}"),
    )

    print("This is inside main() method!")


if __name__ == "__main__":
    ft.app(main)
