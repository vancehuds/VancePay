# VancePay Item Icons

Language: [中文](README.md) | [English](README.en.md)

These icons are drawn for common `ox_inventory` item-image sizes. File names match the default item names:

- `bank_card`
- `portable_pos`
- `vp_tablet`
- `vp_ticket_tablet`
- `vp_debt_tablet`
- `vp_ticket_book`
- `vp_police_ticket`

Directory layout:

- `svg/`: editable source files
- `png/`: bitmap exports ready to copy into your inventory image directory

If you use `ox_inventory`, copy the matching files from `png/` into your item image directory, for example:

```bash
cp assets/item-icons/png/*.png ../[ox]/ox_inventory/web/images/
```

If your inventory resource uses another directory or custom image path, copy the files to that location and keep the file names unchanged.
