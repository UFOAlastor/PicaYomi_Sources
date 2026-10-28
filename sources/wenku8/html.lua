local M={}
function M.new(ctx)
    local codec=ctx.require("codec")
    local H={base="https://www.wenku8.net",cookies={}}
    function H.attr(n,k) return n and n.attributes and n.attributes[k] or "" end
    function H.first(n,q) return n and n:select(q)[1] end
    function H.text(n) return n and (ctx.text.htmlEntitiesToUtf8(n:textonly()):gsub("^%s+",""):gsub("%s+$","")) or "" end
    function H.doc(s) assert(type(s)=="string" and #s>0 and #s<=2*1024*1024);return assert(ctx.html.parse(s,2000000)) end
    function H.id(s) assert(type(s)=="string" and #s<=16 and s:match("^%d+$") and tonumber(s)>0,"invalid ID");return s end
    function H.encode(s) return (s:gsub("([^%w%-_%.~])",function(c)return string.format("%%%02X",c:byte()) end)) end
    function H.query(s) return H.encode(codec.encode(s)) end
    function H.url(s)
        if not s or s=="" then return nil end
        s=ctx.text.htmlEntitiesToUtf8(s)
        if s:sub(1,2)=="//" then s="https:"..s elseif s:sub(1,1)=="/" then s=H.base..s end
        s=s:gsub("^http://","https://")
        assert(s:match("^https://[^/%s]+/") and not s:find("[%c%s]"),"invalid resource URL")
        return s
    end
    function H.page(r)
        local p=r and r.page or 1
        assert(type(p)=="number" and p>=1 and p%1==0 and p<=100000,"invalid page");return p
    end
    function H.fail(code,message,retry) error(ctx.error(code,message,nil,nil,retry),0) end
    local retry_at=0
    function H.request(path,call,method,body,cookies)
        cookies=cookies or H.cookies
        for _=1,5 do
            local remaining=math.ceil(retry_at-ctx.clock.now())
            if remaining>0 then H.fail("rate_limited","站点限制访问频率，请 "..remaining.." 秒后重试",true)end
            assert(type(path)=="string" and path:match("^/[^/]") and not path:find("[%c]"),"invalid same-origin path")
            if call and (call.cancelled or call.isCancelled and call.isCancelled()) then H.fail("cancelled","请求已取消") end
            local timeout=math.min(20,call and call.deadline and call.deadline-ctx.clock.now() or 20)
            if timeout<=0 then H.fail("timeout","请求超时",true) end
            local headers={["User-Agent"]="Dalvik/2.1.0 (Linux; U; Android 12)",
                Accept="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                ["Accept-Language"]="zh-CN,zh;q=0.9",Referer=H.base.."/login.php"}
            if next(cookies) then headers.Cookie=ctx.cookie.toHeader(cookies) end
            if body then headers["Content-Type"]="application/x-www-form-urlencoded" end
            local r,reason=ctx.http:requestOnce(method or "GET",H.base..path,headers,body,timeout)
            local disconnected=type(reason)=="string" and ({closed=true,["connection reset by peer"]=true,["broken pipe"]=true})[reason:lower()]
            if not r and disconnected and (method==nil or method=="GET") and body==nil then
                if call and (call.cancelled or call.isCancelled and call.isCancelled()) then H.fail("cancelled","请求已取消") end
                local remaining=call and call.deadline and call.deadline-ctx.clock.now() or 20
                if remaining<=0 then H.fail("timeout","请求超时",true) end
                r=ctx.http:requestOnce("GET",H.base..path,headers,nil,math.min(20,remaining))
            end
            if not r then H.fail("network","轻小说文库连接失败",true) end
            local status=r.status_code
            if status==403 or type(r.body)=="string" and (r.body:find("cf_chl",1,true) or r.body:find("<title>Just a moment",1,true)) then
                H.fail("unsupported","轻小说文库要求浏览器验证，当前连接无法通过；请稍后重试")
            end
            ctx.cookie.absorb(cookies,r.headers)
            if status==301 or status==302 or status==303 then
                local location=r.headers and (r.headers.location or r.headers.Location)
                assert(type(location)=="string","missing redirect")
                if location:sub(1,#H.base)==H.base then location=location:sub(#H.base+1) end
                assert(location:match("^/[^/]"),"unexpected cross-origin redirect")
                path,method,body=location,"GET",nil
            else
                if status==401 then H.fail("auth_required","请先登录轻小说文库") end
                if status==404 then H.fail("not_found","小说或章节不存在") end
                if status==429 then
                    local wait=tonumber(r.headers and (r.headers["retry-after"] or r.headers["Retry-After"]))
                    wait=wait and wait>0 and wait<86400 and math.ceil(wait) or 5
                    retry_at=ctx.clock.now()+wait
                    H.fail("rate_limited","站点限制访问频率，请 "..wait.." 秒后重试",true)
                end
                if status~=200 then H.fail("network","轻小说文库响应失败",true) end
                assert(type(r.body)=="string" and #r.body>0 and #r.body<=2*1024*1024,"response limit")
                local encoding=r.body:sub(1,4096):lower():match("charset%s*=%s*['\"]?([%w%-]+)")
                return (encoding=="utf-8" or encoding=="utf8") and r.body or codec.decode(r.body)
            end
        end
        H.fail("protocol_changed","站点跳转次数异常")
    end
    function H.get(path,call)
        local html=H.request(path,call)
        local closed_template=html:find("本站正式关闭",1,true) and html:find("2009.03.16-2015.12.24",1,true)
        local login_error=html:find("错误原因",1,true) and (html:find("请先登录",1,true) or html:find("请您先登录",1,true))
        if closed_template or login_error then
            if H.expire then H.expire() end
            H.fail("auth_required","轻小说文库此功能需要登录个人账号")
        end
        if html:find("两次搜索的间隔时间",1,true) then H.fail("rate_limited","站点要求两次搜索至少间隔 5 秒",true) end
        return html
    end
    -- Only an explicit last-page link proves the full server page range.
    function H.paged(doc,current,items,capacity,number)
        local max,last=current,nil
        local links=doc:select("#pagelink a")
        if #links==0 then links=doc:select("a") end
        for _,a in ipairs(links) do
            local n=number(ctx.text.htmlEntitiesToUtf8(H.attr(a,"href")))
            if n then
                max=math.max(max,n)
                if (" "..H.attr(a,"class").." "):find(" last ",1,true) then last=n end
            end
        end
        local result={items=items,has_more=max>current,next=max>current and {page=current+1} or nil}
        local pages=last or (max==current and current or nil)
        if pages then result.pagination={mode="page",page=current,pages=pages,page_size=math.max(capacity,#items,1)} end
        return result
    end
    function H.run(operation,fn,...)
        local ok,value=pcall(fn,...)
        if ok then return true,value,nil end
        if type(value)=="table" and value.code then value.operation=operation;return false,nil,value end
        return false,nil,ctx.error("protocol_changed","轻小说文库数据变化或内容不完整",operation)
    end
    return H
end
return M
