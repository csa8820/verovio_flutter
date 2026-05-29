# Verovio Options 参数完整参考

本文档汇总了 Verovio Toolkit 当前 (third_party/verovio) 全部可配置 options，
包含官方 [Layout options 页面](https://book.verovio.org/advanced-topics/layout-options.html)
未覆盖的输入/选择器/页眉页脚/边距/MIDI/Mensural/Neume 等分组。

数据来源以仓库内 [`third_party/verovio/src/options.cpp`](../third_party/verovio/src/options.cpp)
为准（key / 默认值 / 取值范围 / 枚举值均从源码同步），与 verovio book 上的文字描述对齐。

---

## 1. 在 verovio_flutter 中传入 options

verovio_flutter 通过 JSON 字符串向底层 toolkit 传递参数。常见入口：

```dart
final service = await VerovioAsyncService.spawn(resourcePath: resourcePath);

// 设定全局 options（持久生效，直到再次 set 或 reset）
await service.setOptionsJson(jsonEncode({
  'pageWidth': 2100,
  'pageHeight': 2970,
  'scale': 40,
  'breaks': 'auto',
  'spacingStaff': 8,
  'svgViewBox': true,
}));

// 渲染（沿用上面的 options）
await service.loadData(meiXml);
final svg = await service.renderToSvg(1);

// 一次性 options（仅作用于本次 redoLayout）
await service.redoLayout(jsonEncode({'breaks': 'encoded'}));

// 恢复所有 options 为默认值
await service.resetOptions();
```

辅助方法：
- `getAvailableOptions()` → 返回 toolkit 支持的全部 option（含分组、类型、默认值、范围、枚举），JSON。
- `getDefaultOptions()` → 返回 option 默认值的 JSON。
- `getOptions()` → 返回当前生效 options 的 JSON。

> ⚠️ 注意：
> - 所有 key 大小写敏感（驼峰命名）。
> - 数值型参数若标了「MEI units」或「percent」，取值就是无单位的浮点/整数；
>   只有 `pageWidth/pageHeight/pageMargin*/unit` 这一类标了 `true` 的物理尺寸参数，
>   单位才是 MEI 内部的「百分之一毫米」（即 `pageWidth: 2100` 表示 210 mm = A4 宽）。
> - 同一个参数可以被多次 `setOptions` 覆盖，但部分参数（例如 `font`、`pageWidth`）需要
>   再调用一次 `redoLayout()` 才会反映在 SVG 输出上。

---

## 2. 参数分组速查

Verovio 把参数分成 8 组（见源码里的 `OptionGrp`）：

| 分组                              | 内部 label              | 说明                                       |
| --------------------------------- | ----------------------- | ------------------------------------------ |
| Input and page configuration      | `1-general`             | 输入解析、页面尺寸/边距、SVG 输出特性等    |
| General layout                    | `2-generalLayout`       | 字体、谱线、连音线、动态记号等渲染参数     |
| Loading selectors and processing  | `3-selectors`           | XPath 选择、mdiv 选择、转调                |
| Element margins                   | `4-elementMargins`      | 各 MEI 元素四周的默认/专属边距             |
| Midi options                      | `5-midi`                | MIDI 输出相关                              |
| Mensural notation                 | `6-mensural`            | 中世纪/文艺复兴 Mensural 记谱              |
| Neumatic notation                 | `7-neume`               | 纽姆/GABC 记谱                             |
| Method JSON options               | `7-methodJson`          | 给 toolkit method 传 JSON 参数（如 timemap） |

---

## 3. 输入与页面配置（Input and page configuration）

### 3.1 输入与解析

| Key                          | 类型    | 默认值  | 取值/范围                                       | 说明 |
| ---------------------------- | ------- | ------- | ----------------------------------------------- | ---- |
| `humType`                    | bool    | `false` | —                                               | 从 Humdrum 导入时附带 `@type` 属性 |
| `incip`                      | bool    | `false` | —                                               | 把 `<incip>` 元素当作数据输入读取 |
| `moveScoreDefinitionToStaff` | bool    | `false` | —                                               | 把 scoreDef 上的 clef/keySig/meterSig 等下沉到 staffDef |
| `preserveAnalyticalMarkup`   | bool    | `false` | —                                               | MEI 输出保留分析性标记 |
| `removeIds`                  | bool    | `false` | —                                               | MEI 输出移除未被引用的 xml:id |
| `outputIndent`               | int     | `3`     | 1 – 10                                          | MEI / SVG 输出缩进空格数 |
| `outputIndentTab`            | bool    | `false` | —                                               | 用 Tab 代替空格缩进 |
| `outputFormatRaw`            | bool    | `false` | —                                               | MEI 输出不换行、不缩进 |
| `outputSmuflXmlEntities`     | bool    | `false` | —                                               | 用 XML entity 输出 SMuFL 字符（默认 hex） |
| `xmlIdSeed`                  | int     | `0`     | —                                               | xml:id 随机数种子（CLI 才有意义） |
| `xmlIdChecksum`              | bool    | `false` | —                                               | 用输入数据的校验和作为 xml:id 种子 |
| `setLocale`                  | bool    | `false` | —                                               | 把全局 locale 设为 C（不线程安全） |
| `showRuntime`                | bool    | `false` | —                                               | 在命令行显示运行时长 |

### 3.2 页面尺寸 / 朝向 / 缩放

| Key                | 类型  | 默认值  | 取值/范围                       | 说明 |
| ------------------ | ----- | ------- | ------------------------------- | ---- |
| `pageWidth`        | int   | `2100`  | 100 – 100000（百分之一毫米）    | 页面宽 |
| `pageHeight`       | int   | `2970`  | 100 – 60000                     | 页面高 |
| `pageMarginTop`    | int   | `50`    | 0 – 500                         | 上边距 |
| `pageMarginBottom` | int   | `50`    | 0 – 500                         | 下边距 |
| `pageMarginLeft`   | int   | `50`    | 0 – 500                         | 左边距 |
| `pageMarginRight`  | int   | `50`    | 0 – 500                         | 右边距 |
| `landscape`        | bool  | `false` | —                               | 横屏（交换宽/高） |
| `scaleToPageSize`  | bool  | `false` | —                               | 缩放内容以贴合页面，而不是缩放页面本身 |
| `shrinkToFit`      | bool  | `false` | —                               | 内容超高时向下缩放以适配页面 |
| `unit`             | float | `9`     | 4.5 – 12.0                      | MEI 单位（半个谱线距离） |
| `mmOutput`         | bool  | `false` | —                               | SVG 用 mm 输出（默认 px） |
| `adjustPageHeight` | bool  | `false` | —                               | 把页高调整为内容高度 |
| `adjustPageWidth`  | bool  | `false` | —                               | 把页宽调整为内容宽度 |

### 3.3 分页 / 系统 / 紧排（Condense）

| Key                       | 类型       | 默认值  | 取值                                                                  | 说明 |
| ------------------------- | ---------- | ------- | --------------------------------------------------------------------- | ---- |
| `breaks`                  | enum       | `auto`  | `none` / `auto` / `line` / `smart` / `encoded`                        | 分页与系统换行策略 |
| `breaksSmartSb`           | float      | `0.66`  | 0.0 – 1.0                                                             | smart 模式下使用 encoded sb 的最低系统宽度占比 |
| `condense`                | enum       | `auto`  | `none` / `auto` / `encoded`                                           | 紧排（隐藏空声部）模式 |
| `condenseFirstPage`       | bool       | `false` | —                                                                     | 紧排时也对第一页生效 |
| `condenseNotLastSystem`   | bool       | `false` | —                                                                     | 紧排时不影响最后一个系统 |
| `condenseTempoPages`      | bool       | `false` | —                                                                     | 紧排时也包含含 tempo 变化的页 |
| `evenNoteSpacing`         | bool       | `false` | —                                                                     | 忽略时值进行等距排列 |
| `justifyVertically`       | bool       | `false` | —                                                                     | 垂直方向也做对齐填充 |
| `noJustification`         | bool       | `false` | —                                                                     | 不对系统做横向 justify |
| `minLastJustification`    | float      | `0.8`   | 0.0 – 1.0                                                             | 末系统宽度占比超过该值才做 justify |

### 3.4 页眉 / 页脚

| Key                  | 类型 | 默认值 | 取值                                       | 说明 |
| -------------------- | ---- | ------ | ------------------------------------------ | ---- |
| `header`             | enum | `auto` | `none` / `auto` / `encoded`                | 页眉显示策略 |
| `footer`             | enum | `auto` | `none` / `auto` / `encoded` / `always`     | 页脚显示策略 |
| `usePgHeaderForAll`  | bool | `false`| —                                          | 所有页都用 pgHeader |
| `usePgFooterForAll`  | bool | `false`| —                                          | 所有页都用 pgFooter |

### 3.5 SVG 输出

| Key                       | 类型   | 默认值  | 说明 |
| ------------------------- | ------ | ------- | ---- |
| `svgViewBox`              | bool   | `false` | 在 SVG 根加 viewBox，便于响应式缩放 |
| `svgBoundingBoxes`        | bool   | `false` | 在 SVG 输出 bounding box（含 viewbox） |
| `svgContentBoundingBoxes` | bool   | `false` | 输出内容 bounding box |
| `svgHtml5`                | bool   | `false` | 用 `data-id`/`data-class`，便于 JS 与 ID 冲突避免 |
| `svgFormatRaw`            | bool   | `false` | SVG 输出不换行、不缩进 |
| `svgRemoveXlink`          | bool   | `false` | 移除 href 上的 `xlink:` 前缀 |
| `svgCss`                  | string | `""`    | 注入到 SVG 的额外 CSS |
| `svgAdditionalAttribute`  | array  | `[]`    | 形如 `["note@pname"]`，把对应属性输出成 `data-pname` |

### 3.6 其他外观/行为开关

| Key             | 类型 | 默认值                  | 取值                                | 说明 |
| --------------- | ---- | ----------------------- | ----------------------------------- | ---- |
| `pedalStyle`    | enum | `auto`                  | `auto` / `line` / `pedstar` / `altpedstar` | 全局踏板样式 |
| `smuflTextFont` | enum | `embedded`              | `embedded` / `linked` / `none`      | SMuFL 文本字体的嵌入方式 |
| `neumeAsNote`   | bool | `false`                 | —                                   | Neume 渲染成普通音符 |
| `openControlEvents` | bool | `false`             | —                                   | 渲染未闭合的 control events |
| `staccatoCenter`| bool | `false`                 | —                                   | 跳音/极跳音对齐音符中心 |
| `useBraceGlyph` | bool | `false`                 | —                                   | 使用当前字体的 brace 字形 |
| `useFacsimile`  | bool | `false`                 | —                                   | 使用 `<facsimile>` 信息控制布局 |

---

## 4. 通用排版（General layout）

> 单位说明：除非另注，下表数值的「单位」均为 **MEI units**
> （`unit` 参数所定义的单位，1 unit = 半个谱线距离）。

### 4.1 字体

| Key                  | 类型   | 默认值     | 取值                              | 说明 |
| -------------------- | ------ | ---------- | --------------------------------- | ---- |
| `font`               | string | `Leipzig`  | 安装的 SMuFL 字体名               | 主乐谱字体 |
| `fontAddCustom`      | array  | `[]`       | 自定义字体 zip 路径列表           | 加载额外字体 |
| `fontFallback`       | enum   | `Leipzig`  | `Leipzig` / `Bravura`             | 缺字时回退到哪个字体 |
| `fontLoadAll`        | bool   | `false`    | —                                 | 启动时加载全部字体 |
| `fontTextLiberation` | bool   | `false`    | —                                 | 文本使用 Liberation 字体 |
| `handwrittenFont`    | array  | `[Petaluma]` | —                               | 需要特殊处理的「手写」字体列表 |

### 4.2 谱线 / 小节线

| Key                          | 类型  | 默认值    | 范围        | 说明 |
| ---------------------------- | ----- | --------- | ----------- | ---- |
| `staffLineWidth`             | float | `0.15`    | 0.10 – 0.30 | 谱线粗细 |
| `barLineWidth`               | float | `0.30`    | 0.10 – 0.80 | 小节线粗细 |
| `barLineSeparation`          | float | `0.8`     | 0.5 – 2.0   | 锁定多重小节线之间的间距 |
| `thickBarlineThickness`      | float | `1.0`     | 0.5 – 2.0   | 粗小节线粗细 |
| `dashedBarLineDashLength`    | float | `1.143`   | 0.1 – 5.0   | 虚线小节线 - 实线长度 |
| `dashedBarLineGapLength`     | float | `1.143`   | 0.1 – 5.0   | 虚线小节线 - 间隙长度 |
| `repeatBarLineDotSeparation` | float | `0.36`    | 0.10 – 1.00 | 反复小节线圆点与小节线的距离 |
| `repeatEndingLineThickness`  | float | `0.15`    | 0.10 – 2.0  | 反复/收尾线粗细 |
| `ledgerLineThickness`        | float | `0.25`    | 0.10 – 0.50 | 加线粗细 |
| `ledgerLineExtension`        | float | `0.54`    | 0.20 – 1.00 | 加线向音头两侧延伸的距离 |

### 4.3 符干 / 符尾 / 连音束（Beam）

| Key                  | 类型  | 默认值  | 范围      | 说明 |
| -------------------- | ----- | ------- | --------- | ---- |
| `stemWidth`          | float | `0.20`  | 0.10 – 0.50 | 符干粗细 |
| `beamFrenchStyle`    | bool  | `false` | —         | 法式连音束（符干止于最外侧次梁） |
| `beamMaxSlope`       | int   | `10`    | 0 – 20    | 连音束最大斜率（度） |
| `beamMixedPreserve`  | bool  | `false` | —         | 即使空间不足也保留混合方向连音束 |
| `beamMixedStemMin`   | float | `3.5`   | 1.0 – 8.0 | 混合连音束最小符干长度 |

### 4.4 倚音 / 装饰音 / 多小节休止

| Key                  | 类型  | 默认值 | 范围      | 说明 |
| -------------------- | ----- | ------ | --------- | ---- |
| `graceFactor`        | float | `0.75` | 0.5 – 1.0 | 倚音缩放比例 |
| `graceRhythmAlign`   | bool  | `false`| —         | 倚音跨声部节奏对齐 |
| `graceRightAlign`    | bool  | `false`| —         | 倚音组右端对齐 |
| `multiRestStyle`     | enum  | `auto` | `auto` / `default` / `block` / `symbols` | 多小节休止符样式 |
| `multiRestThickness` | float | `2.0`  | 0.5 – 6.0 | 多小节休止符粗细 |

### 4.5 连音线 / 延音线

| Key                       | 类型  | 默认值 | 范围        | 说明 |
| ------------------------- | ----- | ------ | ----------- | ---- |
| `slurCurveFactor`         | float | `1.0`  | 0.2 – 5.0   | 连线弯曲程度 |
| `slurEndpointFlexibility` | float | `0.0`  | 0.0 – 1.0   | 连线端点位置的灵活度 |
| `slurEndpointThickness`   | float | `0.1`  | 0.05 – 0.25 | 连线端点粗细 |
| `slurMidpointThickness`   | float | `0.6`  | 0.2 – 1.2   | 连线中点粗细 |
| `slurMargin`              | float | `1.0`  | 0.1 – 4.0   | 连线与障碍物的安全距离 |
| `slurMaxSlope`            | int   | `60`   | 30 – 85     | 连线最大斜率（度） |
| `slurSymmetry`            | float | `0.0`  | 0.0 – 1.0   | 连线对称程度 |
| `tieEndpointThickness`    | float | `0.1`  | 0.05 – 0.25 | 延音线端点粗细 |
| `tieMidpointThickness`    | float | `0.5`  | 0.2 – 1.0   | 延音线中点粗细 |
| `tieMinLength`            | float | `2.0`  | 0.0 – 10.0  | 延音线最小长度 |

### 4.6 连音组（Tuplet） / 渐强渐弱（Hairpin）

| Key                       | 类型  | 默认值 | 范围        | 说明 |
| ------------------------- | ----- | ------ | ----------- | ---- |
| `tupletAngledOnBeams`     | bool  | `false`| —           | 仅在连音束上才显示倾斜 tuplet 括号 |
| `tupletBracketThickness`  | float | `0.2`  | 0.1 – 0.8   | tuplet 括号粗细 |
| `tupletNumHead`           | bool  | `false`| —           | tuplet 数字放在符头一侧 |
| `hairpinSize`             | float | `3.0`  | 1.0 – 8.0   | 渐强渐弱开口大小 |
| `hairpinThickness`        | float | `0.2`  | 0.1 – 0.8   | 渐强渐弱线条粗细 |

### 4.7 动态 / 和声 / 八度记号 / 踏板线

| Key                            | 类型  | 默认值 | 范围        | 说明 |
| ------------------------------ | ----- | ------ | ----------- | ---- |
| `dynamDist`                    | float | `1.0`  | 0.5 – 16.0  | 动态记号与谱表的默认距离 |
| `dynamSingleGlyphs`            | bool  | `false`| —           | 不使用 SMuFL 组合 dynamics 字形 |
| `harmDist`                     | float | `1.0`  | 0.5 – 16.0  | 和声标记与谱表的距离 |
| `octaveAlternativeSymbols`     | bool  | `false`| —           | 使用替代八度符号 |
| `octaveLineThickness`          | float | `0.20` | 0.10 – 1.00 | 八度线粗细 |
| `octaveNoSpanningParentheses`  | bool  | `false`| —           | 跨系统八度线不加括号 |
| `pedalLineThickness`           | float | `0.20` | 0.10 – 1.00 | 踏板线粗细 |
| `extenderLineMinSpace`         | float | `1.5`  | 1.5 – 10.0  | 需要绘制延伸线的最小空间 |

### 4.8 歌词（Lyrics）

| Key                   | 类型  | 默认值    | 范围        | 取值                                     | 说明 |
| --------------------- | ----- | --------- | ----------- | ---------------------------------------- | ---- |
| `lyricElision`        | enum  | `regular` | —           | `regular` / `narrow` / `wide` / `unicode`| 联读弧（elision）宽度 |
| `lyricHeightFactor`   | float | `1.0`     | 1.0 – 20.0  | —                                        | 歌词行高系数 |
| `lyricLineThickness`  | float | `0.25`    | 0.10 – 0.50 | —                                        | 歌词延长线粗细 |
| `lyricNoStartHyphen`  | bool  | `false`   | —           | —                                        | 系统起始处不显示连字符 |
| `lyricSize`           | float | `4.5`     | 2.0 – 8.0   | —                                        | 歌词字号 |
| `lyricTopMinMargin`   | float | `2.0`     | 0.0 – 8.0   | —                                        | 歌词上方最小留白 |
| `lyricVerseCollapse`  | bool  | `false`   | —           | —                                        | 折叠空 verse 行 |
| `lyricWordSpace`      | float | `1.2`     | 0.0 – 10.0  | —                                        | 词间空隙 |
| `fingeringScale`      | float | `0.75`    | 0.25 – 1.0  | —                                        | 指法字体缩放 |

### 4.9 系统 / 谱表 / 间距

| Key                          | 类型  | 默认值  | 范围        | 说明 |
| ---------------------------- | ----- | ------- | ----------- | ---- |
| `spacingStaff`               | int   | `12`    | 0 – 48      | 谱表间最小间距 |
| `spacingSystem`              | int   | `4`     | 0 – 48      | 系统间最小间距 |
| `spacingBraceGroup`          | int   | `12`    | 0 – 48      | brace 组内谱表间距 |
| `spacingBracketGroup`        | int   | `12`    | 0 – 48      | bracket 组内谱表间距 |
| `spacingOssia`               | float | `0.35`  | 0.1 – 1.0   | ossia 相对谱表间距的比例 |
| `spacingDurDetection`        | bool  | `false` | —           | 检测长时值以调整间距 |
| `spacingLinear`              | float | `0.25`  | 0.0 – 1.0   | 线性间距系数 |
| `spacingNonLinear`           | float | `0.6`   | 0.0 – 1.0   | 非线性间距系数 |
| `justificationStaff`         | float | `1.0`   | 0.0 – 10.0  | 谱表 justify 权重 |
| `justificationSystem`        | float | `1.0`   | 0.0 – 10.0  | 系统 justify 权重 |
| `justificationBraceGroup`    | float | `1.0`   | 0.0 – 10.0  | brace 组内 justify 权重 |
| `justificationBracketGroup`  | float | `1.0`   | 0.0 – 10.0  | bracket 组内 justify 权重 |
| `justificationMaxVertical`   | float | `0.2`   | 0.0 – 1.0   | 垂直 justify 可用页高比例上限 |
| `bracketThickness`           | float | `1.0`   | 0.5 – 2.0   | bracket 粗细 |
| `subBracketThickness`        | float | `0.20`  | 0.10 – 2.0  | sub-bracket 粗细 |
| `systemDivider`              | enum  | `auto`  | `none` / `auto` / `left` / `left-right` | 系统分隔符显示 |
| `systemMaxPerPage`           | int   | `0`     | 0 – 24      | 每页最多系统数（0 = 不限） |
| `breaksNoWidow`              | bool  | `false` | —           | 避免最后一页只有一个小节 |
| `ossiaStaffSize`             | float | `0.75`  | 0.5 – 1.0   | ossia 谱表大小比例 |
| `measureMinWidth`            | int   | `15`    | 1 – 30      | 小节最小宽度 |
| `mnumInterval`               | int   | `0`     | 0 – 64      | 小节号显示间隔（0 = 默认行为） |
| `textEnclosureThickness`     | float | `0.2`   | 0.10 – 0.80 | 文本外框粗细 |

### 4.10 SMuFL Engraving defaults

| Key                      | 类型              | 默认值 | 说明 |
| ------------------------ | ----------------- | ------ | ---- |
| `engravingDefaults`      | JSON string       | `{}`   | 直接给 SMuFL 默认值（JSON 字符串） |
| `engravingDefaultsFile`  | filepath string   | `""`   | SMuFL 默认值的 JSON 文件路径 |

---

## 5. 选择器与处理（Selectors）

| Key                           | 类型    | 默认值 | 说明 |
| ----------------------------- | ------- | ------ | ---- |
| `appXPathQuery`               | array   | `[]`   | 选择 `<app>` 子元素的 XPath，例如 `"./rdg[contains(@source,'src1')]"` |
| `choiceXPathQuery`            | array   | `[]`   | 选择 `<choice>` 子元素的 XPath，例如 `"./orig"` |
| `substXPathQuery`             | array   | `[]`   | 选择 `<subst>` 子元素的 XPath，例如 `"./del"` |
| `mdivXPathQuery`              | string  | `""`   | 选择要渲染的 mdiv（只能选一个） |
| `mdivAll`                     | bool    | `false`| 渲染所有 mdiv |
| `loadSelectedMdivOnly`        | bool    | `false`| 仅加载选中的 mdiv，跳过其他 |
| `expand`                      | string  | `""`   | 按 xml:id 展开 `<expansion>` |
| `expandAlways`                | bool    | `false`| 对所有输出（含 MIDI/timemap）都展开 |
| `expandNever`                 | bool    | `false`| 任何输出都不展开 |
| `ossiaHidden`                 | bool    | `false`| 渲染时隐藏 ossia |
| `transpose`                   | string  | `""`   | 全曲移调 |
| `transposeMdiv`               | JSON    | `{}`   | 按 mdiv id 分别指定移调 |
| `transposeSelectedOnly`       | bool    | `false`| 只对选中的内容移调，忽略未选 editorial |
| `transposeToSoundingPitch`    | bool    | `false`| 按 `@trans.semi` 移调到 sounding pitch |

---

## 6. 元素边距（Element margins）

所有数值单位均为 **MEI units**，默认范围 0.0 – 2.0（除非另注）。

### 6.1 全局默认

| Key                  | 默认值 | 范围     |
| -------------------- | ------ | -------- |
| `defaultTopMargin`   | `0.5`  | 0.0 – 6.0 |
| `defaultBottomMargin`| `0.5`  | 0.0 – 5.0 |
| `defaultLeftMargin`  | `0.0`  | 0.0 – 2.0 |
| `defaultRightMargin` | `0.0`  | 0.0 – 2.0 |

### 6.2 元素专属上/下边距

| Key                    | 默认值 | 范围        | 适用元素 |
| ---------------------- | ------ | ----------- | -------- |
| `topMarginArtic`       | `0.75` | 0.0 – 10.0  | artic |
| `bottomMarginArtic`    | `0.75` | 0.0 – 10.0  | artic |
| `topMarginHarm`        | `1.0`  | 0.0 – 10.0  | harm |
| `bottomMarginHarm`     | `1.0`  | 0.0 – 10.0  | harm |
| `bottomMarginOctave`   | `1.0`  | 0.0 – 10.0  | octave |
| `bottomMarginHeader`   | `2.0`  | 0.0 – 24.0  | pgHead |
| `topMarginPgFooter`    | `2.0`  | 0.0 – 24.0  | pgFooter |

### 6.3 元素专属左/右边距

下列每个元素都同时存在 `leftMarginXxx` 和 `rightMarginXxx`，含义相同。
默认值可能不同，详见源码 [`options.cpp`](../third_party/verovio/src/options.cpp)。

可用元素列表：`accid` / `barLine` / `beatRpt` / `chord` / `clef` / `keySig` /
`leftBarLine` / `mensur` / `meterSig` / `mRest` / `mRpt2` / `multiRest` /
`multiRpt` / `note` / `rest` / `rightBarLine` / `tabDurSym`。

典型默认值：`leftMarginAccid = 1.0`、`rightMarginAccid = 0.5`、`leftMarginNote = 1.0`、
`rightMarginNote = 0.0`。

---

## 7. MIDI 输出

| Key                    | 类型   | 默认值 | 范围      | 说明 |
| ---------------------- | ------ | ------ | --------- | ---- |
| `midiNoCue`            | bool   | `false`| —         | MIDI 输出跳过 cue 音符 |
| `midiTempoAdjustment`  | float  | `1.0`  | 0.2 – 4.0 | MIDI 速度调整系数 |
| `tuningFile`           | string | `""`   | —         | 自定义 tuning 定义或 tuning 文件路径 |

---

## 8. Mensural 记谱

| Key                       | 类型 | 默认值   | 取值                                       | 说明 |
| ------------------------- | ---- | -------- | ------------------------------------------ | ---- |
| `durationEquivalence`     | enum | `brevis` | `brevis` / `semibrevis` / `minima`         | Mensural 时值等价 |
| `ligatureAsBracket`       | bool | `false`  | —                                          | Ligature 渲染成括号 |
| `ligatureOblique`         | enum | `auto`   | `auto` / `straight` / `curved`             | Ligature oblique 形状 |
| `mensuralResponsiveView`  | enum | `auto`   | `none` / `auto` / `selection`              | 响应式 Mensural（selection 会丢弃 ligature 与 editorial） |
| `mensuralToCmn`           | bool | `false`  | —                                          | 把 Mensural 转成 CMN 小节制 MEI |
| `mensuralScoreUp`         | bool | `false`  | —                                          | 通过 `@dur.quality` 推算声部 score-up |

---

## 9. Neume / GABC

| Key                       | 类型 | 默认值 | 范围 | 说明 |
| ------------------------- | ---- | ------ | ---- | ---- |
| `gabcAquitanianContext`   | bool | `false`| —    | GABC `V` 左符干使用 `tilt="ne"`（而不是 `n`） |
| `gabcExtendedSymbols`     | bool | `false`| —    | 启用 S-GABC 扩展符号（`r`、`"`） |
| `gabcStaffLines`          | int  | `4`    | 4 – 5 | GABC 谱线数（对应 GABC `staff-lines:` 头） |
| `liquescentWithoutTails`  | bool | `false`| —    | liquescent 头不带尾 |

---

## 10. Method JSON 参数

这些参数本身就是 JSON 字符串，会被一并交给具体 method。

| Key              | 类型        | 默认值 | 说明 |
| ---------------- | ----------- | ------ | ---- |
| `timemapOptions` | JSON string | `{}`   | 生成 timemap 时的 JSON 参数（包含 `includeRests`、`includeMeasures`、`useFractions` 子键） |

### 10.1 `timemapOptions` 是干嘛的

它**不参与排版**，专门是给 `renderToTimemap()` 这个 method 传的 JSON 子参数。
timemap 是 verovio 输出的"时间映射表"，按时间顺序列出乐谱里**每个音符开/关、休止符、小节、速度变化**的事件，主要用于**播放同步**（MIDI 一边响一边在 SVG 上高亮当前音符）。

来源：[verovio/src/toolkit.cpp](../third_party/verovio/src/toolkit.cpp) 在 `RenderToTimemap` 中只识别这三个子 key。

| 子 key            | 类型 | 默认  | 作用 |
| ----------------- | ---- | ----- | ---- |
| `includeMeasures` | bool | false | 输出 `measureOn` 字段（该时间点哪个小节开始） |
| `includeRests`    | bool | false | 输出 `restsOn` / `restsOff`（默认只输出音符） |
| `useFractions`    | bool | false | 时间戳改用 `qfrac:[分子,分母]` 精确分数，而不是 `qstamp` 浮点 |

### 10.2 两种传参方式

**A. 通过 setOptions（命令行 / 持久化场景）**

```dart
await service.setOptionsJson(jsonEncode({
  // 注意：值是字符串化的 JSON，不是嵌套对象
  'timemapOptions': jsonEncode({
    'includeMeasures': true,
    'includeRests':    true,
    'useFractions':    false,
  }),
}));
final mapJson = await service.renderToTimemap();
```

**B. 直接传给 method（推荐，JS / Dart 都支持）**

```dart
final mapJson = await service.renderToTimemap(
  options: {'includeMeasures': true, 'includeRests': true},
);
```

两种等效，B 更直观、不用做字符串嵌套。

### 10.3 `renderToTimemap` 返回结构

返回值是一个 **JSON 数组**，按时间顺序排列，每项是一个"时间点事件"。
所有字段确认自 [timemap.h](../third_party/verovio/include/vrv/timemap.h) 的 `TimemapEntry` 与 [timemap.cpp](../third_party/verovio/src/timemap.cpp) 的 `ToJson()`。

```jsonc
[
  {
    "qstamp":    0,                          // 节拍位置（四分音符为 1）
    "tstamp":    0,                          // 实际时间（毫秒，受 tempo 影响）
    "tempo":     120,                        // 速度，仅在变化时出现
    "on":        ["note-001", "note-002"],   // 此刻开始发声的音符 xml:id
    "off":       ["note-998"],               // 此刻结束发声的音符 xml:id
    "restsOn":   ["rest-005"],               // 仅 includeRests:true
    "restsOff":  ["rest-004"],               // 仅 includeRests:true
    "measureOn": "measure-3"                 // 仅 includeMeasures:true
  }
]
```

#### 时间字段

| 字段     | 类型       | 含义 |
| -------- | ---------- | ---- |
| `qstamp` | number     | **节拍位置**。从曲首起算，单位"四分音符 = 1"。与速度无关，纯节拍位置 —— 适合做乐理分析、节奏处理 |
| `qfrac`  | [num, den] | 仅 `useFractions:true` 时出现。同义但用**精确分数**避免浮点误差（如三连音第 2 音是 `[5,3]` 而不是 `1.666666…`）。出现 `qfrac` 时**不再出 `qstamp`**，二者互斥 |
| `tstamp` | number     | **实际毫秒时间**。从曲首起算，**受 tempo 影响** —— 速度越快增长越慢。**这是 MIDI 同步、音频对齐时实际使用的字段** |

> 速记：`qstamp` = 拍子位置；`tstamp` = 真实毫秒。播放高亮用 `tstamp`，乐理分析用 `qstamp`。

#### 事件字段（核心）

| 字段       | 类型     | 含义 |
| ---------- | -------- | ---- |
| `on`       | string[] | 此时刻**开始发声**的音符 xml:id 列表。可能多个（和弦、多声部） |
| `off`      | string[] | 此时刻**结束发声**的音符 xml:id 列表。和 `on` 不一定同时出现 |
| `restsOn`  | string[] | 此刻开始的休止符 xml:id。**仅 `includeRests:true`** |
| `restsOff` | string[] | 此刻结束的休止符 xml:id。**仅 `includeRests:true`** |

注意：
- 数组里的 ID 就是 **SVG `<g>` 元素的 id**，直接 `document.getElementById(id)` 拿到对应节点做高亮。
- 一个时间点经常**同时有 `off` 和 `on`** —— 表示前一个音结束、下一个音开始（典型旋律）。
- 字段名是缩写 `on` / `off`，**不是** `notesOn` / `notesOff`（那是 C++ struct 内部名）。

#### 元信息字段

| 字段        | 类型   | 何时出现 | 含义 |
| ----------- | ------ | -------- | ---- |
| `tempo`     | number | **仅速度变化时** | BPM（按四分音符）。第一个事件总有一次（初始速度），之后只在 tempo mark 变化时再出 —— **不变就不重复**。要拿"任意时刻速度"需在遍历时维护变量 |
| `measureOn` | string | `includeMeasures:true` 且该时间点是小节起始 | 进入的小节 xml:id，可做"跳到第 N 小节"或滚动到当前小节 |

### 10.4 完整样例

C 大调 4/4 ♩=120，两小节："C4 D4 E4 F4 ｜ G4 A4 ♩休 C5"，开启全部选项：

```jsonc
[
  { "qstamp": 0, "tstamp": 0,    "tempo": 120,
    "on": ["n-c4"], "measureOn": "m-1" },
  { "qstamp": 1, "tstamp": 500,
    "off": ["n-c4"], "on": ["n-d4"] },
  { "qstamp": 2, "tstamp": 1000,
    "off": ["n-d4"], "on": ["n-e4"] },
  { "qstamp": 3, "tstamp": 1500,
    "off": ["n-e4"], "on": ["n-f4"] },
  { "qstamp": 4, "tstamp": 2000,
    "off": ["n-f4"], "on": ["n-g4"], "measureOn": "m-2" },
  { "qstamp": 5, "tstamp": 2500,
    "off": ["n-g4"], "on": ["n-a4"] },
  { "qstamp": 6, "tstamp": 3000,
    "off": ["n-a4"], "restsOn":  ["r-1"] },
  { "qstamp": 7, "tstamp": 3500,
    "restsOff": ["r-1"], "on": ["n-c5"] },
  { "qstamp": 8, "tstamp": 4000,
    "off": ["n-c5"] }
]
```

### 10.5 典型用法：MIDI 播放 + 音符高亮

```dart
// 1. 加载 + 渲染 + 取 timemap + 取 MIDI
await service.loadData(meiXml);
final svg     = await service.renderToSvg(1);
final midiB64 = await service.renderToMidi();
final mapJson = await service.renderToTimemap(
  options: {'includeMeasures': true, 'includeRests': false},
);
final map = jsonDecode(mapJson) as List;

// 2. 播放器按 tstamp 喂事件，UI 按 xml:id 高亮
int cursor = 0;
player.onPositionMs.listen((ms) {
  while (cursor < map.length && map[cursor]['tstamp'] <= ms) {
    final ev = map[cursor];
    (ev['on']  as List?)?.forEach(highlight);
    (ev['off'] as List?)?.forEach(unhighlight);
    if (ev['measureOn'] != null) scrollToMeasure(ev['measureOn']);
    cursor++;
  }
});
```

对应 SVG 侧的 CSS：

```css
.playing { fill: #4f46e5 !important; }
```

### 10.6 用法对照表

| 场景             | 关键字段                                            |
| ---------------- | --------------------------------------------------- |
| 播放高亮音符     | `tstamp` + `on` + `off`                             |
| 高亮当前小节     | `tstamp` + `measureOn`（需 `includeMeasures:true`） |
| 跳转第 N 小节    | `measureOn`，找到匹配后用 `tstamp` 喂播放头         |
| 节奏 / 乐理分析  | `qstamp` 或 `qfrac`（**别用 `tstamp`**，受速度干扰）|
| 速度曲线绘图     | 收集所有出现 `tempo` 字段的事件                     |
| 节拍器同步       | 相邻 `tstamp` 间距 → 当前每拍长度                   |
| 三连音 / 复杂节奏 | 开 `useFractions:true`，用 `qfrac`                  |

### 10.7 注意点

1. **字段名是 `on` / `off`**，不是 `notesOn` / `notesOff`。
2. **`tempo` 不重复输出**，要自己维护"当前速度"变量。
3. **休止符默认不输出**，避免 timemap 过大；需要时打开 `includeRests:true`。
4. **xml:id 必须能在 SVG 里找到** —— 如果开启了 `svgHtml5:true`，id 会被改成 `data-id`，要用 `querySelector('[data-id="..."]')` 而不是 `getElementById`。
5. **`tstamp` 起点是 0**，不是 MIDI 文件的 offset。播放器若有 pre-roll / 延迟需自己叠加。

---

## 11. 基础短参数（命令行专用，CLI-only）

只在命令行 `verovio` 工具里生效，verovio_flutter 用不到，仅列出以备查阅：

`help`、`allPages`、`inputFrom`、`logLevel`、`outfile`、`outputTo`、`page`、
`resourcePath`、`scale`、`standardOutput`、`version`。

（其中 `scale` 在 verovio_flutter 里可以通过 `setOptionsJson({"scale": 50})` 当作普通
option 使用，对应「输出整体缩放百分比，默认 100」。）

---

## 12. 常用配方（Cookbook）

### 12.1 自适应宽高 + 一行一系统

```dart
await service.setOptionsJson(jsonEncode({
  'adjustPageHeight': true,
  'adjustPageWidth': true,
  'breaks': 'auto',
  'svgViewBox': true,
}));
```

### 12.2 移动端竖屏 A4

```dart
await service.setOptionsJson(jsonEncode({
  'pageWidth': 2100,     // 210mm
  'pageHeight': 2970,    // 297mm
  'pageMarginTop': 50,
  'pageMarginBottom': 50,
  'pageMarginLeft': 50,
  'pageMarginRight': 50,
  'scale': 40,
  'breaks': 'auto',
  'spacingStaff': 8,
  'spacingSystem': 6,
}));
```

### 12.3 横屏铺满

```dart
await service.setOptionsJson(jsonEncode({
  'landscape': true,
  'adjustPageHeight': true,
  'svgViewBox': true,
  'breaks': 'encoded',
}));
```

### 12.4 关闭页眉/页脚（嵌入 UI 常用）

```dart
await service.setOptionsJson(jsonEncode({
  'header': 'none',
  'footer': 'none',
  'pageMarginTop': 20,
  'pageMarginBottom': 20,
}));
```

### 12.5 只渲染某个 mdiv + 自动移调

```dart
await service.setOptionsJson(jsonEncode({
  'mdivXPathQuery': "./mdiv[@xml:id='mdiv-2']",
  'transpose': 'P5',
}));
```

### 12.6 给 SVG 节点加 data-* 属性（用于交互）

```dart
await service.setOptionsJson(jsonEncode({
  'svgHtml5': true,
  'svgViewBox': true,
  'svgAdditionalAttribute': ['note@pname', 'note@oct'],
}));
```

---

## 13. 排查 & 进一步阅读

1. 想确认运行时实际生效的参数：调用 `getOptions()`，对比 `getDefaultOptions()`。
2. 想看完整 schema（含分组、type、min/max）：调用 `getAvailableOptions()`。
3. 参数没生效：
   - 改了 layout 类参数后，需要 `redoLayout()` 才能反映在 SVG。
   - `font` 改完后请确认目标字体已通过 `fontAddCustom` 注册，或已在内置字体目录中。
   - 部分参数（如 `setLocale`、`xmlIdSeed`）只在 CLI 工具有意义。
4. 官方文档：
   - [Verovio Book - Layout options](https://book.verovio.org/advanced-topics/layout-options.html)
   - [Verovio Book - Toolkit methods](https://book.verovio.org/toolkit-reference/toolkit-methods.html)
   - 仓库内最权威来源：[`third_party/verovio/src/options.cpp`](../third_party/verovio/src/options.cpp)
