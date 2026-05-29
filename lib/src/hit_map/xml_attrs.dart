import 'package:xml/xml_events.dart';

import 'package:verovio_flutter/src/hit_map/shape_bbox.dart';

/// package:xml 的属性适配器，直接按属性名读取值。
///
/// 支持 `qualifiedName` 与 `localName` 两种查找方式，兼容 `xlink:href`
/// 这类带前缀的属性名。
class XmlEventAttrs implements ShapeAttrs {
  const XmlEventAttrs(this.attributes);

  final List<XmlEventAttribute> attributes;

  @override
  String? operator [](String name) {
    for (final XmlEventAttribute attr in attributes) {
      if (attr.qualifiedName == name || attr.localName == name) {
        return attr.value;
      }
    }
    return null;
  }
}
