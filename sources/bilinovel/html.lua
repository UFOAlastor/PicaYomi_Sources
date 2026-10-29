-- Small source-local HTTP/HTML helpers; no host modules or browser execution.
local M={}
function M.new(ctx,base)
    local H={base=base,cookies={night="0"}}
    function H.attr(n,k) return n and n.attributes and n.attributes[k] or "" end
    function H.first(n,q) return n and n:select(q)[1] end
    function H.text(n) return n and (ctx.text.htmlEntitiesToUtf8(n:textonly()):gsub("^%s+",""):gsub("%s+$","")) or "" end
    function H.doc(s) assert(type(s)=="string" and #s>0 and #s<=2*1024*1024);return assert(ctx.html.parse(s,2000000)) end
    function H.id(s) assert(type(s)=="string" and #s<=32 and s:match("^%d+$"),"invalid ID");return s end
    function H.encode(s) return (s:gsub("([^%w%-_%.~])",function(c)return string.format("%%%02X",c:byte()) end)) end
    function H.url(s)
        if not s or s=="" then return nil end
        s=ctx.text.htmlEntitiesToUtf8(s)
        if s:sub(1,2)=="//" then s="https:"..s elseif s:sub(1,1)=="/" then s=base..s end
        assert(s:match("^https://[^/%s]+/") and not s:find("[%c%s]"),"invalid resource URL")
        return s
    end
    function H.page(r)
        local p=r and r.page or 1
        assert(type(p)=="number" and p>=1 and p%1==0 and p<=1000000,"invalid page")
        return p
    end
    function H.firstPage(r) assert(H.page(r)==1,"pagination unavailable") end
    function H.unsupported(message) error(ctx.error("unsupported",message),0) end
    function H.fail(code,message,retry) error(ctx.error(code,message,nil,nil,retry),0) end
    function H.request(path,call,method,body,extra,cookies)
        cookies=cookies or H.cookies
        for _=1,5 do
            assert(type(path)=="string" and path:sub(1,1)=="/" and path:sub(1,2)~="//" and not path:find("[%c]"),"invalid same-origin path")
            if call and (call.cancelled or call.isCancelled and call.isCancelled()) then H.fail("cancelled","请求已取消") end
            local timeout=math.min(20,call and call.deadline and call.deadline-ctx.clock.now() or 20)
            if timeout<=0 then H.fail("timeout","请求超时",true) end
            local headers={["User-Agent"]="Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
                Accept="*/*",["Accept-Language"]="zh-CN,zh;q=0.9",Referer=base.."/",
                ["Accept-Encoding"]="gzip",Cookie=ctx.cookie.toHeader(cookies)}
            for k,v in pairs(extra or {}) do headers[k]=v end
            if body then headers["Content-Type"]="application/x-www-form-urlencoded" end
            local r,reason=ctx.http:requestOnce(method or "GET",base..path,headers,body,timeout)
            -- A public GET interrupted before its response may be tried once.
            -- Never replay login/search POSTs, TLS alerts or HTTP rejections.
            local disconnected=type(reason)=="string" and ({closed=true,["connection reset by peer"]=true,["broken pipe"]=true})[reason:lower()]
            if not r and disconnected and (method==nil or method=="GET") and body==nil then
                if call and (call.cancelled or call.isCancelled and call.isCancelled()) then H.fail("cancelled","请求已取消") end
                local remaining=call and call.deadline and call.deadline-ctx.clock.now() or 20
                if remaining<=0 then H.fail("timeout","请求超时",true)end
                r=ctx.http:requestOnce("GET",base..path,headers,nil,math.min(20,remaining))
            end
            if not r then H.fail("network","小说站连接失败",true) end
            ctx.cookie.absorb(cookies,r.headers)
            local status=r.status_code
            if status==301 or status==302 or status==303 then
                local location=r.headers and (r.headers.location or r.headers.Location)
                assert(type(location)=="string","missing redirect")
                if location:sub(1,#base)==base then location=location:sub(#base+1) end
                assert(location:sub(1,1)=="/" and location:sub(1,2)~="//","unexpected cross-origin redirect")
                path,method,body=location,"GET",nil
            else
                if status==403 then H.unsupported("站点要求浏览器验证，当前源无法访问") end
                if status==401 then H.fail("auth_required","当前内容需要登录") end
                if status==404 then H.fail("not_found","内容不存在") end
                if status==429 then H.fail("rate_limited","站点请求过于频繁",true) end
                if status~=200 then H.fail("network","小说站响应失败",true) end
                assert(type(r.body)=="string" and #r.body<=2*1024*1024,"response too large")
                if r.body:find("<title>Just a moment",1,true) then H.unsupported("站点要求浏览器验证") end
                return r.body,path
            end
        end
        H.fail("protocol_changed","站点跳转次数异常")
    end
    function H.get(path,call)
        local html=H.request(path,call)
        local form=html:find('name="frmlogin"',1,true) and html:find('name="password"',1,true)
        if form then
            local code=H.logged and H.logged() and "auth_expired" or "auth_required"
            if H.expire then H.expire() end
            H.fail(code,"哔哩轻小说此功能需要登录个人账号")
        end
        return html
    end
    local last_search,search_cache
    local search_routes,route_order={},{}
    function H.search(keyword,page,call)
        local cache_key=keyword.."\0"..page
        if search_cache and search_cache.key==cache_key and ctx.clock.now()-search_cache.time<120 then return search_cache.html,search_cache.path end
        local route=page>1 and search_routes[keyword] or nil
        if page>1 and (not route or page>route.pages) then H.fail("invalid_response","搜索分页信息已失效，请重新搜索")end
        if page==1 and last_search and ctx.clock.now()-last_search<5 then
            error(ctx.error("rate_limited","两次搜索请至少间隔 5 秒",nil,nil,true),0)
        end
        if not H.cookies.jieqiSearchTicket then
            local headers={Referer=base.."/search.html"}
            local landing=H.request("/search.html",call,nil,nil,headers)
            -- Packed script tokens 0/2 are dictionary references to css/js,
            -- including inside quoted strings; they are not endpoint values.
            local css,js,redeem="css","js","redeem"
            H.request("/search.html?search_guard="..css,call,nil,nil,headers)
            local script=H.request("/search.html?search_guard="..js,call,nil,nil,headers)
            -- The normal search page loads a script assigning one opaque,
            -- anonymous search cookie. Parse that string; never execute it.
            local quoted=script:match('document%.cookie%s*=%s*("jieqiSearchJs=[^"]+")')
            if not quoted then
                H.fail("unsupported","站点搜索需要浏览器验证，当前未取得搜索许可；请在原站确认后稍后重试")
            end
            local cookie=ctx.json.decode(quoted)
            local value=cookie:match("^jieqiSearchJs=([%w%._%-]+);")
            assert(value and #value<=1024,"invalid search cookie")
            H.cookies.jieqiSearchJs=value
            H.request("/search.html?search_guard="..redeem.."&r="..math.floor(ctx.clock.timestamp()*1000),call,nil,nil,headers)
            if not H.cookies.jieqiSearchTicket then H.unsupported("站点搜索验证尚未完成，请稍后重试") end
        end
        last_search=ctx.clock.now()
        local ok,html,path
        if page>1 then
            ok,html,path=pcall(H.request,route.stem.."_"..page..".html",call,nil,nil,{Referer=base.."/search.html"})
        else
            local body="searchkey="..H.encode(keyword).."&page="..page
            ok,html,path=pcall(H.request,"/search.html",call,"POST",body,{Referer=base.."/search.html"})
        end
        -- A ticket is consumed even when the request fails. Never reuse it.
        H.cookies.jieqiSearchTicket=nil
        if not ok then error(html,0)end
        if html=="" then
            H.cookies.jieqiSearchTicket=nil
            error(ctx.error("rate_limited","搜索会话失效或请求过于频繁，请稍后重试",nil,nil,true),0)
        end
        local stem=html:match('href="(/search/[^"%s?#]+)_%d+%.html"')
        local current,pages=html:match("第%s*(%d+)%s*/%s*(%d+)%s*页")
        if stem and tonumber(current)==page and tonumber(pages) and tonumber(pages)<=1000000 then
            if not search_routes[keyword] then route_order[#route_order+1]=keyword end
            search_routes[keyword]={stem=stem,pages=tonumber(pages)}
            if #route_order>4 then search_routes[table.remove(route_order,1)]=nil end
        end
        return html,path
    end
    function H.rememberSearch(keyword,page,html,path)
        search_cache={key=keyword.."\0"..page,time=ctx.clock.now(),html=html,path=path}
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
        return false,nil,ctx.error("protocol_changed","小说站数据结构变化或返回内容不完整",operation)
    end
    return H
end
return M
