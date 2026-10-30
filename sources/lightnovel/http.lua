local M={}
function M.new(ctx)
    local H={base='https://www.lightnovel.fun'}
    -- These POST endpoints only read data. Never replay authentication or
    -- bookshelf mutations, even when the server closes without a response.
    local readonly={
        ['bff/apk-search-result-v1']=true,['bff/home-promo-v1']=true,
        ['bff/home-recent-updates-feed-v1']=true,['bff/apk-search-taxonomy-v1']=true,
        ['bff/book-rank-list-v1']=true,['bff/bookshelf-v1']=true,
        ['new-content-read/get-book-library-state']=true,
        ['new-content-read/get-book-detail']=true,['new-content-read/get-book-volumes']=true,
        ['new-content-read/get-volume-chapters']=true,['new-content-read/get-chapter-detail']=true,
        ['new-content-read/check-book-download-access']=true,['new-content-read/get-book-comments']=true,
    }
    function H.fail(code,text,retry)error(ctx.error(code,text,nil,nil,retry),0)end
    function H.run(operation,fn)
        local ok,value=pcall(fn)
        if ok then return true,value,nil end
        if type(value)=='table' and value.code then value.operation=operation;return false,nil,value end
        return false,nil,ctx.error('protocol_changed','轻之国度数据结构变化或内容不完整',operation)
    end
    function H.id(v)
        v=tostring(v or '');assert(v:match('^%d+$') and #v<=16 and tonumber(v)>0,'invalid ID');return v
    end
    function H.page(r)
        local p=r and r.page or 1;assert(type(p)=='number' and p>=1 and p%1==0 and p<=1000000);return p
    end
    function H.cancel(call)
        if call and (call.cancelled or call.isCancelled and call.isCancelled())then H.fail('cancelled','请求已取消')end
    end
    function H.post(path,args,call,options)
        options=options or {};H.cancel(call)
        assert(path:match('^[%w_/%-]+$'))
        local body={};for k,v in pairs(args)do body[k]=v end
        local token=not options.anonymous and H.token and H.token()
        if token then body.security_key=token end
        local origin=options.comments and 'https://api.lightnovel.fun/pc-comment-proxy/api/' or H.base..'/api/pc-proxy/api/'
        local resp,reason
        local payload=ctx.json.encode(body)
        for attempt=1,2 do
            H.cancel(call)
            local timeout=math.min(20,call and call.deadline and call.deadline-ctx.clock.now() or 20)
            if timeout<=0 then H.fail('timeout','请求超时',true)end
            resp,reason=ctx.http:requestOnce('POST',origin..path,{['Content-Type']='application/json',Accept='application/json',Referer=H.base..'/',Origin=H.base},payload,timeout)
            H.cancel(call)
            if resp or reason~='closed' or not readonly[path] or options.login or attempt==2 then break end
        end
        H.cancel(call)
        if not resp then H.fail('network','轻之国度请求失败',true)end
        if resp.status_code==401 then
            if token and H.expire then H.expire()end
            H.fail(token and 'auth_expired' or 'auth_required','站点要求重新登录')
        end
        if resp.status_code==403 then H.fail('auth_required','站点限制本次访问，请在网页确认验证要求')end
        if resp.status_code==429 then H.fail('rate_limited','站点限制访问频率，请稍后重试',true)end
        if resp.status_code~=200 then H.fail('network','轻之国度请求失败（HTTP '..tostring(resp.status_code)..'）',true)end
        assert(type(resp.body)=='string' and #resp.body<=4*1024*1024)
        local value=ctx.json.decode(resp.body);assert(type(value)=='table' and type(value.code)=='number')
        if value.code~=0 then
            if value.code==8 then
                if token and H.expire then H.expire()end
                H.fail(token and 'auth_expired' or 'auth_required','轻之国度要求重新登录')
            end
            -- Login failures can contain credential echoes. Never forward them.
            if options.login then
                if value.code==1001 then H.fail('auth_required','账号不存在或密码错误，请在网页确认登录信息')end
                H.fail('auth_required','站点未允许登录（代码 '..value.code..'），请在网页确认账号或验证要求')
            end
            local d=type(value.data)=='table' and value.data or {}
            local message=value.message or value.msg or d.message
            if type(message)=='string' and #message<=240 and not message:find('[<>%c]') then
                message=ctx.redact.text(message)
                if token then message=message:gsub(token:gsub('([^%w])','%%%1'),'[redacted]')end
                H.fail('network',message)
            end
            H.fail('network','轻之国度未允许本次请求（代码 '..value.code..'）')
        end
        assert(type(value.data)=='table');return value.data
    end
    function H.pagination(d,p,size)
        local q=d.pagination
        if not q and type(d.page_info)=='table' then
            local i=d.page_info;q={page=i.cur,page_size=i.size,total=i.count,page_count=type(i.count)=='number' and math.ceil(i.count/size)}
        end
        assert(type(q)=='table' and q.page==p and q.page_size==size)
        assert(type(q.total)=='number' and q.total>=0 and q.total%1==0)
        assert(type(q.page_count)=='number' and q.page_count>=0 and q.page_count<=1000000)
        assert(type(d.list)=='table' and #d.list<=size)
        local more=p<q.page_count;assert(not more or #d.list>0,'empty middle page')
        return more,q
    end
    return H
end
return M
