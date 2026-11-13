// 生成 App 图标素材：从 assets/icon_src.png 产出
//   assets/icon.png      —— 1024x1024 满幅方形图标
//   assets/icon_fg.png   —— 1024x1024 自适应图标前景（画面居中占 66%，四周留白）
// 跑法：dart run tool/make_icon_assets.dart

import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final bytes = File('assets/icon_src.png').readAsBytesSync();
  final src = img.decodePng(bytes);
  if (src == null) {
    stderr.writeln('解码失败：assets/icon_src.png 不是合法 PNG');
    exit(1);
  }

  // 居中裁成正方形
  final int side = src.width < src.height ? src.width : src.height;
  final int ox = (src.width - side) ~/ 2;
  final int oy = (src.height - side) ~/ 2;
  final img.Image square = img.copyCrop(
    src,
    x: ox,
    y: oy,
    width: side,
    height: side,
  );

  // 满幅图标（传统 launcher 用）
  final img.Image full = img.copyResize(
    square,
    width: 1024,
    height: 1024,
    interpolation: img.Interpolation.cubic,
  );
  File('assets/icon.png').writeAsBytesSync(img.encodePng(full));

  // 自适应图标前景：整张 1024 画布，画面只占中间 66%——
  // 系统圆形遮罩只显示中间 72/108，不缩进去的话脸会被裁掉
  const int canvas = 1024;
  const int inner = (canvas * 2 ~/ 3);
  final img.Image fg = img.Image(width: canvas, height: canvas);
  img.fill(fg, color: img.ColorRgb8(255, 255, 255));
  final img.Image pic = img.copyResize(
    square,
    width: inner,
    height: inner,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(fg, pic, dstX: (canvas - inner) ~/ 2, dstY: (canvas - inner) ~/ 2);
  File('assets/icon_fg.png').writeAsBytesSync(img.encodePng(fg));

  stdout.writeln('已生成 assets/icon.png 和 assets/icon_fg.png');
}
