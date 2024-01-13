import logging

import flet as ft
from flet_core.version import version

logging.basicConfig(level=logging.DEBUG)

print("Hello from Python!")

# import aaa

print("Hello again from Python!")


def main(page: ft.Page):
    page.title = "Flet counter example"
    page.vertical_alignment = ft.MainAxisAlignment.CENTER

    txt_number = ft.TextField(value="0", text_align=ft.TextAlign.RIGHT, width=100)

    def minus_click(e):
        txt_number.value = str(int(txt_number.value) - 1)
        page.update()

    def plus_click(e):
        txt_number.value = str(int(txt_number.value) + 1)
        page.update()

    page.add(
        ft.Row(
            [
                ft.IconButton(
                    ft.icons.REMOVE, key="test:decrement", on_click=minus_click
                ),
                txt_number,
                ft.IconButton(ft.icons.ADD, key="test:increment", on_click=plus_click),
            ],
            alignment=ft.MainAxisAlignment.CENTER,
            expand=True,
        ),
        ft.Row(
            [ft.Text(f"Flet version: {version}")],
            alignment=ft.MainAxisAlignment.CENTER,
        ),
    )

    print("This is inside main() method!")


ft.app(main)
