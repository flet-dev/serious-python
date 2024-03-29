import logging

import flet as ft

logging.basicConfig(level=logging.DEBUG)


async def main(page: ft.Page):
    page.title = "Flet counter example"
    page.vertical_alignment = ft.MainAxisAlignment.CENTER

    txt_number = ft.TextField(value="0", text_align=ft.TextAlign.RIGHT, width=100)

    async def minus_click(e):
        txt_number.value = str(int(txt_number.value) - 1)
        await page.update_async()

    async def plus_click(e):
        txt_number.value = str(int(txt_number.value) + 1)
        await page.update_async()

    await page.add_async(
        ft.Row(
            [
                ft.IconButton(
                    ft.icons.REMOVE, key="test:decrement", on_click=minus_click
                ),
                txt_number,
                ft.IconButton(ft.icons.ADD, key="test:increment", on_click=plus_click),
            ],
            alignment=ft.MainAxisAlignment.CENTER,
        )
    )


ft.app(main)
