# API v3 小说源（宿主 1.1 起）

小说源沿用 `.pysource` 包、账号、在线收藏和只读评论接口，通过 `content_type="novel"` 指定内容类型。manifest 必须声明 `api_version=3`、`min_app_version>=1.1.0`，作品与章节使用站点稳定 ID。

## 正文接口

小说实现 `getChapterContent(book_id,chapter_id,call)`，代替漫画必需的 `getPages`。成功返回标准三元组，data 为：

```lua
{format="html",html="<p>章节正文</p>",base_url="https://example.invalid/book/42/101.html",complete=true}
```

`base_url` 是公开章节地址，用于解析相对插图路径，不能含凭据。源先验证正文完整、访问条件和全部同章分页；付费预览、访问验证页或残章返回明确错误，不能标成完整章节。章节 HTML 上限 256 KiB。

宿主负责白名单清理、保留图文顺序、下载插图、原子保存完整文档，并交给 KOReader 文本引擎阅读。插图通过 `getImageRequest` 按请求生成头部；凭据和请求头不进入离线清单。支持 PNG/JPEG，以及转换为本地 PNG 的 WebP；单图最多 4 MiB/4M 像素、每章 64 图、总资源 12 MiB。

## 可选能力

- `download=true`：宿主下载选择页和队列保存完整 HTML 与插图；未完整保存不标为已下载。离线阅读使用文档清单，不调用假的图片页接口。
- `login=true`：实现 login/logout/getSession/getUserProfile。getSession 只读取本地会话状态，不在界面查询时联网；实际请求识别过期状态并返回 auth_expired。
- `favorites=true`：实现完整在线书架分页、明确的加入/移除收藏；按站点规则声明 `access={favorites="login"}`。本地收藏由宿主管理。
- `comments=true`：只读评论；分页回复另外声明 `replies="paged"` 并实现 getCommentReplies。不开启不存在的功能，不实现发表。

网页登录需要逐跳处理 Set-Cookie 时，可用 `ctx.http:requestOnce(method,url,headers,body,timeout)` 取得单次 HTTPS 响应，自行验证同源 Location 后继续。此调用不自动跟随重定向、不重试登录提交；沿用宿主异步任务、取消和超时。Cookie 使用 SDK 隔离的加密 secrets 保存，不保存密码，不把凭据转发到图片 CDN 或站外验证地址。

完整 SDK、返回约定与包发布规则见 [契约](CONTRACT.md)和[发布说明](PUBLISHING.md)。

### 评论预览与全文（1.1.0）

沿用漫画详情的查看评论入口和公共只读评论页。如果站点列表只有主题或缩略正文，返回 `content_complete=false`，实现 `getCommentDetails` 并声明 `comment_details=true`；全文需要登录时单独声明该能力的访问条件。宿主仅在点击时获取全文，关闭或换账号取消，不逐条抓取。`replies="paged"` 必须有真实回复协议；所有源均不实现发表或回复写入。接口见 [契约](CONTRACT.md)。
