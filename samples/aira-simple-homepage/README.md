# Aira 简洁主页

这是基于 Aira 官方起步模板制作的日常使用版主页，可直接打包导入 Aira。

## 面向用户的调整

- 搜索框直接提交搜索词或网址，不显示额外的 A 按钮。
- 搜索引擎由 Aira 设置统一管理，主页不再提供切换控件。
- 快捷方式无需进入排序模式：长按浮起后图标跟随手指移动，邻近图标会弹性让位，拖到网格边缘可自动滚动，松手落位回弹并一次性保存完整顺序。
- 长按后不移动并松手，只打开主页自己的打开、复制、编辑和删除菜单。
- “添加”作为快捷方式网格的最后一个圆形项目展示。
- 保留快捷方式打开、复制链接、编辑和删除能力。
- 保留扫一扫、主页、书签、标签页和设置入口。

## 打包

在本目录执行：

```bash
zip -X -r ../aira-simple-homepage.zip \
  aira-homepage.json index.html preview-light.jpg preview-dark.jpg assets
```

ZIP 根目录必须直接包含 `aira-homepage.json`。不要把 `README.md`、外层目录、隐藏文件或 `.git` 打进主页包。

## License

[MIT](LICENSE)。主页包内同时包含 `assets/LICENSE.txt`。
