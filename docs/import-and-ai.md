# 导入与设备端 AI：可实施设计

状态：方案已批准。本文件是实施规格。桌面小组件、iCloud、界面、语言和灵活提醒先作为一个可验证的改动；标准 CSV/JSON 导入、再然后可选的 Kimi/DeepSeek 字段映射，分后续改动，不塞进同一个巨型变更。未实现的阶段不会出现能点的空按钮。没有 Key、不发网络请求时，记录和同步保持完整。

核对日期：2026-11-21。供应商的地址、模型和价格以当天官方文档为准；价格会变，实现时要再打开文中的官方页面，不要把本文件里的数字写死成唯一真相。

## 现有代码里有什么

记录只有一套 Core Data：`Baby`（uuid、name、birthDate、createdAt）和 `LogEvent`（uuid、kind、start/end、备注，以及按类型分开的奶量、尿布、泵奶、生长、药物字段）。编辑用 `EventDraft`，取消不落库。没有导入器，没有导入批次，也没有外部记录 id。

`CSVExporter` 能把全部记录导出成一份 CSV：

- 列是英文标题，类型用的是界面标题（`Sleep`、`Nursing`），不是 `EventKind` 的 raw value。
- 日期是带时区偏移的 ISO-8601。没有单独的时区名，也没有事件 uuid、宝宝 uuid。
- 数量单位写死为 ml、kg、cm；0 导出成空单元格。
- 单元格按 RFC 4180 加引号，并以 `'` 挡住以 `= + - @` 开头的公式。
- 设置里「Export all data (CSV)」把这份文件丢进系统分享。没有对应的读入。

因此现在的 CSV 不能当作导入契约：缺版本、缺稳定 id、类型和空值都有损。它只说明「我们自己导出的旧文件」以后可以做一个有损的兼容读取器，不能宣称能导入某个其他 App。仓库里也没有那些 App 的真实样本。

单位换算已经存在，导入应复用而不是再写一套：`VolumeUnit.milliliters(from:)`（盎司→毫升），`UnitSystem.kilograms(pounds:ounces:)`。

提醒设置在本机 `UserDefaults`，不进 CloudKit。API Key 以后也不能走这条或 iCloud。

## 原则

1. 没有 Key、AI 关闭时，记录、本地存储、iCloud 业务同步、标准文件导入都完整可用。
2. 不设后端，不代用户申请供应商账号。Key 由用户自己填写。
3. 文件和模型回复都是不可信数据。不执行其中的指令，不把历史备注或文件正文拼进系统提示当命令。
4. 模型不拿到工具定义，不能调用函数，不能写 Core Data。它只返回候选；本地校验通过后仍要人确认。
5. 时间和数量缺了就留空并标成待核，不补一个看起来合理的值。
6. 导入只新增。不覆盖、不改写、不删除已有记录。同一时刻的另一条合法记录（另一类型，或同类型但数量/尿布/食物不同）不是重复，不能删。
7. 不声称兼容任何具体的第三方 App。

## 第一期最小范围（建议先做，仍不含 AI）

只做本地、版本化的标准文件。两种容器，同一套中间模型：

- JSON：`schema` 必须是 `littlebabylog.import`，`schemaVersion` 必须是 `1`。
- CSV：第一行是列名。文件开头可以用一行 `# littlebabylog.import 1` 声明版本；没有这行时，列名必须能全部对上标准列，否则整份拒绝，不猜。

明确不做：PDF、图片、未知表头、AI、自定义 endpoint、自动写记录。

解析失败时列出文件和原因，已能识别的行留在预览里标错，不把错行静默丢掉，也不把整份变成 0 条还显示成功。

### 标准 schema 1

编码只接受 UTF-8。带 BOM 可以。别的编码直接拒绝并说明，不猜 GBK。

日期只接受带偏移的 ISO-8601（`2026-03-10T09:03:00+08:00`）。偏移就是那条记录的时区；不另用「手机当前时区」去解释一个没有偏移的本地时间。没有偏移的时间是错误，不是「大概是北京时间」。跨日睡眠用 `start` 和 `end` 两个瞬时，允许 end 落在下一天。end 早于 start 是错误。

数量的规范单位是 ml、kg、cm、秒。文件可以用 `unit` 声明 `ml`/`oz`、`kg`/`lb`，换算走现有 `VolumeUnit` / `UnitSystem`。换不出的单位是该单元格的错误。0 和空要分开：空是未填，0 是用户写了 0。

宝宝：每行有 `babyName`，可选 `babyId`（UUID）。预览里按 UUID 优先、否则按去掉首尾空白后的大小写不敏感名字，对应到本机已有宝宝。对不上的名字逐个让人指定「用已有宝宝」或「新建」。不因为文件里出现一个名字就静默建宝宝。文件里的名字只作标签，不作指令。

类型用 `EventKind` 的 raw value：`sleep`、`breastfeed`、`bottle`、`solids`、`diaper`、`pump`、`growth`、`medicine`。瓶内容 `formula` / `breastMilk` / `other`。尿布 `wet` / `dirty` / `mixed` / `dry`。未知值留在该行的 `unknown` 列表里，不映射成一个默认类型。

可选 `externalId`：来源文件自己的稳定 id。没有也可以导入。

CSV 标准列（顺序可变，名字必须一致）：

`schemaVersion,babyName,babyId,externalId,kind,start,end,amountML,amountUnit,bottleContent,leftSeconds,rightSeconds,diaper,food,pumpedLeftML,pumpedRightML,weightKg,lengthCm,headCm,medicine,dose,notes`

JSON 形状：

```json
{
  "schema": "littlebabylog.import",
  "schemaVersion": 1,
  "rows": [ { "babyName": "月月", "kind": "bottle", "start": "2026-03-10T09:03:00+08:00", "amountML": 40, "amountUnit": "ml", "bottleContent": "formula" } ]
}
```

我们自己今天导出的那份 CSV 不是 schema 1。以后如果要读它，单独做 `legacy-own-export` 读取器，并在预览里写明：没有 uuid、类型是英文标题、空单元格可能是 0。那仍然不是「兼容某某 App」。

### 中间模型

解析结果先变成纯值，不碰 `NSManagedObjectContext`。

- `ImportRow`：来源定位（文件内行号，从 1 起）、原始单元格、解析出的字段、`issues`。
- `ImportIssue`：`error` 或 `needsReview`。错误行默认不导入；待核行默认不导入，人可以改完再选。
- `ImportDraft`：准备写入的字段，对应 `EventDraft` 能表达的内容，外加 `babyID`、`externalId`、来源行号。
- `ImportPreview`：将导入 / 将跳过 / 错误 / 待核 / 未知值 / 重复候选的计数，以及宝宝映射表。
- `ImportBatch`：人确认时生成的 UUID。写入成功后记住本批新建事件的 uuid。

校验在草稿上做，不在模型里做：类型允许的字段、数量范围（例如毫升 0...2000 之外标待核而不是改小）、日期能构成 `Date`、睡眠和其它有时长的类型可以跨日但 end 不得早于 start、单位能换算。范围常量要写在一个地方并有测试，不要散落在界面里。

### 重复、事务、撤销

重复分两种，都要测：

- 幂等：本机已有事件带相同 `externalId`（同一宝宝）。再次导入时跳过，不新建、不修改、不删除那条旧记录。
- 候选：没有 externalId 时，同一宝宝、同一 kind、同一 start（精确到秒）且区分字段也相同（奶量、瓶内容、尿布、食物名、药名和剂量）。预览里列为候选，默认跳过，人可以改成「仍要新建」。同一秒但 kind 不同，或 kind 相同但奶量不同，只是并列的合法记录，不进候选，更不能删。

确认后在一个 `NSManagedObjectContext` 里插入全部选中行，一次 `save`。保存失败则 `rollback`，库回到确认前。不逐条保存。

撤销本批：只删除「uuid 属于本批，且 `modifiedAt` 仍等于导入时写入的值」的事件。人已经改过的留下，并告诉他留下了几条。撤销不删除批次以外的任何记录。

建议的模型增量（第一期实现时才加，这次没加）：`LogEvent.importBatchID: UUID?`、`LogEvent.externalID: String?`，均可空，轻量迁移。原始文件不入库，不进 CloudKit。批次 id 和 external id 会随记录同步，这样另一台设备不会把同一 external id 再插一遍；这不是把文件或 Key 同步出去。

## 第二期：别的格式，仍然先本地抽取

未知 CSV/JSON 先在本地读出表头、分隔符、样例行。人可以手动把列映射到 schema 1 的字段。映射可以保存为「这一份文件的映射」，下次同一表头可复用。映射不全时，未映射列出现在预览里，不丢弃不声响。

PDF 和图片只承诺系统框架实际做得到的事：

- 有文字层的 PDF：PDFKit 抽出文字。产品限额建议单文件 20 MB、最多 30 页；超出的页不读，并在预览里写明停在哪一页。
- 扫描版 PDF：把页面画成图，再用 Vision 的 `VNRecognizeTextRequest`（`.accurate`，语言 zh-Hans 与 en）。建议最多 10 页，避免内存尖峰。
- 照片：JPEG/PNG/HEIC，建议最多 5 张，同样走 Vision。
- Vision 给出的是文本行和置信度，不是可靠的表格。不做「还原对方 App 的版面」的承诺。
- 每一行保留来源：PDF 页码加行序，或第几张图。置信度低于阈值，或一行里找不到可解析的时间和数量时，该字段留空，标 `needsReview`。禁止用相邻行或常识填上一个时间或毫升数。

DeepSeek 文档里有文件解析/OCR 接口（见下）。本设计不使用它，也不使用 Kimi 的文件上传接口，因为那会把整份原始文件交给供应商。OCR 留在设备上。

这一期仍不调用模型。手动映射就是 AI 失败时的同一条退路。

## 第三期：可选的 Kimi / DeepSeek，只做字段映射

AI 默认关。打开它要同时满足：人打开开关、Keychain 里有对应供应商的 Key、每次发送前都有一张确认页。没有「后台看到新文件就上传」。

模型的任务只有一件：看本地已经抽出的、脱敏后的表头和少量样例，提议「源列 → schema 1 字段」。不让它返回完整记录，不让它填时间或毫升。本地解析器用这份映射去读整个文件；单元格解析失败就变成该行的错误，不把原值交给模型补全。

发给模型的内容上限要硬编码并有测试：表头，加上最多 8 行；备注、药名、剂量、食物名、宝宝姓名在发出前替换成占位符（`Baby A`、`[text]`）。用户确认页必须列出：供应商和固定地址、将发送的字段名、脱敏后的样例全文、是否仍可能含可识别信息。人可以改成「只发列名、不发样例」。每一轮点一次才发送。不宣传供应商零留存；确认页写明数据会按该供应商当时的条款离开这台设备。

映射结果进 `MappingProposal`：每列一个目标字段或 `unmapped`，外加 0...1 的置信度。解码只认这些键。多出来的键丢弃。JSON 解析失败、空内容、或出现具体时间/数量，都视为失败并展示原因，预览回到手动映射或标准模板，不把文件标成已导入。

### 官方接口（2026-11-21 核对）

只使用下面两个固定主机。Key 不能跟着重定向走。URLSession 要拒绝跳到别的 host。不发送 `tools`。

Kimi，国际文档 [Quickstart](https://platform.kimi.ai/docs/api/quickstart) 与 [Chat](https://platform.kimi.ai/docs/api/chat)：

- `POST https://api.moonshot.ai/v1/chat/completions`
- 中文文档 [快速开始](https://platform.kimi.com/docs/api/quickstart) 的主机是 `https://api.moonshot.cn/v1/chat/completions`
- 这是两个平台。界面分成「Kimi 国际」和「Kimi 中国站」，各存各的 Key，只发到对应的固定 URL。不能把一边的 Key 发到另一边，也不能发到用户随便填的地址。
- 文档中的当前对话模型包括 `kimi-k3.1-pro`、`kimi-k3.1-pro-highspeed`、`kimi-k3`。第一期适配器只用 `kimi-k3.1-pro`。K2 系列文档写明 2026-10-31 起不再向新用户提供，并计划 2026 年 12 月底下线，不要用。
- 结构化输出：`response_format` 支持 `json_object` 和 `json_schema`（见同一 Chat 文档）。映射请求用 `json_schema` 且 `strict: true`。`json_object` 仍要求提示里写明字段。
- [定价页](https://platform.kimi.ai/docs/pricing/chat) 确认：K3 上下文 1,048,576 token；按量计费；缓存默认 TTL 5 分钟，另有 1 小时；`kimi-k3.1-pro` 与 `kimi-k3` 的 Batch 为标准价的 60%；文件抽取接口当时标为暂时免费，但抽取出的正文作为模型输入仍按 token 计费。本次抓取没有带出该页的数字价目表，所以这里不记录美元单价。设置页链到该官方页，不在 App 里写死一个未核对到的单价。

DeepSeek，[首调用](https://api-docs.deepseek.com/)、[Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)、[JSON Output](https://api-docs.deepseek.com/guides/json_mode/)、[价格](https://api-docs.deepseek.com/quick_start/pricing)：

- `POST https://api.deepseek.com/chat/completions`。不要用 Anthropic 兼容路径。
- 模型用 `deepseek-flash`。文档写明它由 DeepSeek-V4.1-Flash-1017 提供。`deepseek-v4-pro` 更贵，不做默认。
- JSON 只有 `{"type":"json_object"}`，没有在该页看到 `json_schema`。提示里必须出现单词 json 和一个例子。`max_tokens` 要设上，避免被截断。文档说明：若输出不像 JSON，接口会把非 JSON 换成空格，`content` 可能看起来是空的，即使 `finish_reason` 是 `stop`。空内容要当失败并允许重试一次，不能当成「没有行」。
- 映射请求设 `thinking: {"type":"disabled"}`，避免默认思考模式拉高时延和输出 token。不传 `tools`，因此不触发文档里的网页搜索。
- 2026-11-21 官方价格页（每 1M token，会变）：`deepseek-flash` 输入缓存命中高峰 $0.006 / 非高峰 $0.003，缓存未中高峰 $0.30 / 非高峰 $0.15，输出高峰 $1.20 / 非高峰 $0.60。高峰为周一至周五 01:00–04:00 与 06:00–10:00 UTC，不含中国法定假日。上下文 1M，最大输出 384K。我们自己的预算远小于此。
- 同页文件解析/OCR 为每 1000 页 $0.225。不调用。

费用说明放在确认页：这次会发送大约多少字符、输出上限多少 token、DeepSeek 用上面的官方单价估一个区间、Kimi 写「以官方定价页为准」并给出链接。实际扣费以供应商账单为准。App 不代充值。

### 调用协议

一个协议，两个适配器。适配器里没有宝宝、没有 Core Data。

- 固定 endpoint、固定模型、超时（建议 30 秒）、取消（`Task`）、对 429 和 5xx 最多再试一次。不跟随跨主机重定向。
- 请求体只有 system（代码里的固定短句）和一条 user（已脱敏的表头和样例）。不附带聊天历史，不附带别的记录的备注。
- 响应先过 JSON 解码和 schema 校验，再交给预览。校验失败是可见错误。

自定义 OpenAI 兼容地址不在前三期。若以后做：只允许 https；每个地址一把独立 Key；禁止把 Kimi 或 DeepSeek 的 Key 发到该地址；同样拒绝跨主机重定向；默认关闭。

### Key

只放 Keychain。`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，`kSecAttrSynchronizable = false`，不进 iCloud 钥匙串，不进备份同步。服务名固定，账户名是供应商 id（`kimi-ai`、`kimi-cn`、`deepseek`）。

设置页：输入时覆盖、保存后只显示末四位、用一个不含宝宝数据的最小请求测试连接、可删除。Key 不进日志、不进分析、不进仓库、不进小组件快照、不进 CloudKit。测试连接的响应也不要原样写入日志。

本设计没有读取、写入或验证任何真实 Key。

## 全 App 复用时只做三件草稿

同一套协议以后可以再做三件事，每一件都是草稿，人保存才落库或才改提醒。不在这一轮做。

1. 自然语言变成一条记录草稿（仍走 `EventDraft`，打开现有编辑器）。
2. 对用户明确点选的日期范围做文字摘要。不默认把全部历史发出去；发出前同样走确认页和脱敏。
3. 自然语言变成一条提醒规则草稿，打开提醒编辑器。不直接调用 `UNUserNotificationCenter`。

不做：婴幼儿医疗判断、喂养或喝水的处方、自动改已有记录、自动开关通知。喝水提醒继续是照护者自己的目标，不是婴儿喝水建议。文件或摘要里的句子不能变成后续请求的系统提示。

## 测试验收

第一期就该有的，全部是本地、确定性、无网络：

- schema 1 的 JSON 和 CSV 往返字段；错误版本、非 UTF-8、无偏移日期被拒绝。
- `+08:00` 的 23:30 不会被解释成另一天；睡眠跨午夜保留 start/end。
- oz 换成毫升与 `VolumeUnit` 一致；未知单位成为该行错误，行还在预览里。
- 未知 kind、未知尿布值留在未知列表，不变成默认值。
- 宝宝名字映射：两个已有宝宝，文件里一个对上、一个对不上；对不上的在确认前不会被创建。
- 相同 externalId 第二次导入不新增；同秒同类型同奶量是候选且默认不插入；同秒不同奶量两条都在；导入不修改、不删除导入前的记录。
- 确认后一次保存；保存失败回滚后条数与确认前相同。撤销只删除本批未改记录。
- 公式样的单元格（`=cmd`）当文本存，不执行。

第二期：PDF 文字层按页保留行序；OCR 空字段保持待核；超过页数限额时多出的页有明确计数。用夹具，不用真实的其他 App 导出，不断言某个 App 的列名。

第三期：用假的 `URLProtocol` 或适配器测试双主机、拒绝重定向、不发送 tools、JSON 不合 schema 时预览不变、空 content 不算成功、脱敏后的样例不含宝宝原名。不在测试里放真实 Key，不打到 api.moonshot.ai、api.moonshot.cn 或 api.deepseek.com。

## 不在本轮做的事

不改 Core Data 来加导入字段，不加设置入口，不引入 Keychain 封装，不增加网络权限用途，不申请供应商账号，不上传 TestFlight。桌面小组件、iCloud、界面和提醒仍按原范围实现；本文件不替代那些工作。
