# VancePay 物品图标

语言：[中文](README.md) | [English](README.en.md)

这些图标按 `ox_inventory` 常见物品图尺寸绘制，文件名与默认物品名保持一致：

- `bank_card`
- `portable_pos`
- `vp_tablet`
- `vp_ticket_tablet`
- `vp_debt_tablet`
- `vp_ticket_book`
- `vp_police_ticket`

目录说明：

- `svg/`: 可继续编辑的源文件
- `png/`: 可直接复制到物品栏图片目录的位图导出文件

如果你在用 `ox_inventory`，把 `png/` 里的同名文件复制到你的物品图片目录，例如：

```bash
cp assets/item-icons/png/*.png ../[ox]/ox_inventory/web/images/
```

如果你的库存资源使用其他目录或自定义图片路径，保持文件名不变并复制到对应位置即可。
