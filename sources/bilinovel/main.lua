return function(ctx)
    -- Public pages moved together. Keep the original account origin and its
    -- stored cookies separate; a public migration never moves credentials.
    local H=ctx.require("html").new(ctx,"https://www.bilinovel.net")
    local account_http=ctx.require("html").new(ctx,"https://www.bilinovel.com")
    local search_http=ctx.require("html").new(ctx,"https://www.bilinovel.net")
    local D=ctx.require("decoder")
    local account=ctx.require("account").new(ctx,account_http)
    local comments=ctx.require("comments").new(ctx,H,account,account_http)
    local last_detail,recommended,script_cache
    local parse_book
    local S={capabilities={recommendations=true,latest=true,search=true,categories=true,
        local_favorites=true,login=true,favorites=false,comments=true,comment_details=true,replies="none",download=true},
        access={comment_details="login"}}
    function S:init()account.restore();return true,{success=true},nil end
    function S:getSession()return true,{logged_in=account.logged()},nil end
    function S:login(username,password,call)return H.run("login",account.login,username,password,call)end
    function S:logout()return H.run("logout",account.logout)end
    function S:getUserProfile(call)return H.run("getUserProfile",account.profile,call)end
    function S:getComments(id,request,call)return H.run("getComments",comments.list,id,request,call)end
    function S:getCommentDetails(id,rid,call)return H.run("getCommentDetails",comments.details,id,rid,call)end
    local function meta(doc,property)
        for _,n in ipairs(doc:select("meta")) do if H.attr(n,"property")==property then return H.attr(n,"content") end end
    end
    local function list(html,page,home,search)
        local doc=H.doc(html);local items,seen={},{}
        for _,a in ipairs(doc:select(home and "a.module-slide-a" or "a.book-layout")) do
            local id=H.attr(a,"href"):match("^/novel/(%d+)%.html$")
            if id and not seen[id] then
                local title=H.text(H.first(a,home and ".module-slide-caption" or ".book-title"))
                assert(title~="","missing list title");seen[id]=true
                local image=H.first(a,"img")
                local author=H.text(H.first(a,".book-author")):gsub("^作者%s*","")
                local url=H.attr(image,"data-src");if url=="" then url=H.attr(image,"src") end
                items[#items+1]={id=id,title=title,author=author,cover=H.url(url),description=H.text(H.first(a,".book-desc"))}
            end
        end
        if #items==0 then assert(H.text(doc):find("没有找到",1,true) or H.text(doc):find("共有 0",1,true),"unrecognized empty book list") end
        if home then return {items=items,has_more=false,total=#items,pagination={mode="page",page=1,pages=1,page_size=math.max(1,#items)}} end
        if search then
            local current,pages=H.text(H.first(doc,"#pagelink")):match("第%s*(%d+)%s*/%s*(%d+)%s*页")
            current,pages=tonumber(current),tonumber(pages)
            if current and pages then
                assert(current==page and pages>=page and pages<=1000000,"unexpected search page")
                local total=tonumber(H.text(doc):match("共有%s*(%d+)%s*条记录"))
                if total and math.ceil(total/30)~=pages then total=nil end
                return {items=items,total=total,has_more=page<pages,next=page<pages and {page=page+1} or nil,
                    pagination={mode="page",page=page,pages=pages,page_size=30}}
            end
        end
        return H.paged(doc,page,items,30,function(href)
            return tonumber(href:match("^/top/[%w_]+/(%d+)%.html$") or href:match("^/wenku/[%w_]+_(%d+)_0%.html$") or href:match("[?&]page=(%d+)"))
        end)
    end
    function S:getRecommendations(request,call)
        return H.run("getRecommendations",function()
            if request and request.sort then
                local sort=request.sort;assert(({weekvisit=true,monthvisit=true,weekvote=true,monthvote=true,lastupdate=true,words=true,goodnum=true,postdate=true})[sort],"invalid sort")
                local p=H.page(request)
                return list(H.get("/wenku/"..sort.."_0_0_0_0_0_0_0_"..p.."_0.html",call),p)
            end
            H.firstPage(request)
            if recommended and ctx.clock.now()-recommended.time<120 then return ctx.json.decode(recommended.json) end
            local result=list(H.get("/",call),1,true)
            recommended={time=ctx.clock.now(),json=ctx.json.encode(result)};return result
        end)
    end
    function S:getLatest(request,call)
        return H.run("getLatest",function()local p=H.page(request);return list(H.get("/top/lastupdate/"..p..".html",call),p)end)
    end
    function S:search(keyword,request,call)
        return H.run("search",function()
            assert(type(keyword)=="string" and #keyword>0 and #keyword<=512,"invalid search")
            local p=H.page(request)
            local html,path=search_http.search(keyword,p,call)
            local direct=path and path:match("^/novel/(%d+)%.html$")
            local result
            if direct then
                assert(p==1,"unexpected redirected search page")
                local doc=H.doc(html)
                local item=parse_book(doc,direct)
                last_detail={id=direct,time=ctx.clock.now(),html=html}
                result={items={item},total=1,has_more=false,pagination={mode="page",page=1,pages=1,page_size=1}}
            else result=list(html,p,false,true)end
            search_http.rememberSearch(keyword,p,html,path)
            return result
        end)
    end
    local categories={{id="0",title="全部"},{id="1",title="电击文库"},{id="2",title="富士见文库"},
        {id="3",title="角川文库"},{id="4",title="MF文库J"},{id="5",title="Fami通文库"},
        {id="6",title="GA文库"},{id="7",title="HJ文库"},{id="8",title="一迅社文库"},
        {id="9",title="集英社"},{id="10",title="小学馆"},{id="11",title="讲谈社"},
        {id="12",title="少女文库"},{id="13",title="其他文库"},{id="14",title="华文轻小说"},{id="15",title="Web轻小说"}}
    local sorts={{id="lastupdate",title="最近更新"},{id="weekvisit",title="周人气"},{id="monthvisit",title="月人气"},{id="weekvote",title="周推荐"},{id="monthvote",title="月推荐"},{id="words",title="字数"},{id="goodnum",title="收藏数"},{id="postdate",title="最新入库"}}
    -- Verified site topic catalogue (2026-10-27); keeping the picker offline.
    local topics={
        {id="tag:64",title="恋爱"},
        {id="tag:48",title="后宫"},
        {id="tag:63",title="校园"},
        {id="tag:27",title="百合"},
        {id="tag:26",title="转生"},
        {id="tag:47",title="异世界"},
        {id="tag:15",title="奇幻"},
        {id="tag:61",title="冒险"},
        {id="tag:222",title="欢乐向"},
        {id="tag:231",title="女性视角"},
        {id="tag:219",title="龙傲天"},
        {id="tag:96",title="魔法"},
        {id="tag:67",title="青春"},
        {id="tag:31",title="性转"},
        {id="tag:198",title="病娇"},
        {id="tag:217",title="妹妹"},
        {id="tag:225",title="青梅竹马"},
        {id="tag:18",title="战斗"},
        {id="tag:256",title="NTR"},
        {id="tag:223",title="人外"},
        {id="tag:227",title="大小姐"},
        {id="tag:189",title="黑暗"},
        {id="tag:68",title="悬疑"},
        {id="tag:56",title="科幻"},
        {id="tag:201",title="伪娘"},
        {id="tag:55",title="战争"},
        {id="tag:185",title="萝莉"},
        {id="tag:229",title="复仇"},
        {id="tag:199",title="斗智"},
        {id="tag:131",title="异能"},
        {id="tag:241",title="猎奇"},
        {id="tag:191",title="轻文学"},
        {id="tag:60",title="职场"},
        {id="tag:226",title="经营"},
        {id="tag:246",title="JK"},
        {id="tag:135",title="机战"},
        {id="tag:261",title="女儿"},
        {id="tag:221",title="末日"},
        {id="tag:220",title="犯罪"},
        {id="tag:239",title="旅行"},
        {id="tag:124",title="惊悚"},
        {id="tag:98",title="治愈"},
        {id="tag:97",title="推理"},
        {id="tag:205",title="日本文学"},
        {id="tag:248",title="游戏"},
        {id="tag:228",title="耽美"},
        {id="tag:211",title="美食"},
        {id="tag:245",title="群像"},
        {id="tag:249",title="大逃杀"},
        {id="tag:233",title="音乐"},
        {id="tag:132",title="格斗"},
        {id="tag:28",title="热血"},
        {id="tag:180",title="温馨"},
        {id="tag:224",title="脑洞"},
        {id="tag:328",title="恶役"},
        {id="tag:304",title="JC"},
        {id="tag:254",title="间谍"},
        {id="tag:146",title="竞技"},
        {id="tag:263",title="宅文化"},
        {id="tag:333",title="同人"},
    }
    local topic_ids={}
    for _,topic in ipairs(topics)do topic_ids[topic.id]=true end
    function S:getCategories()
        local out=ctx.json.decode(ctx.json.encode(topics))
        for _,category in ipairs(categories)do out[#out+1]=ctx.json.decode(ctx.json.encode(category)) end
        return true,out,nil
    end
    function S:getSortOptions(kind)
        if kind=="recommend" then return true,{{id="weekvisit",title="周人气"},{id="weekvote",title="周推荐"},{id="monthvisit",title="月人气"},{id="monthvote",title="月推荐"},{id="words",title="字数"}},nil end
        return true,kind=="category" and sorts or {},nil
    end
    function S:getCategoryComics(id,request,call)
        return H.run("getCategoryComics",function()
            local tag,publisher="0","0"
            if topic_ids[id] then tag=id:sub(5)
            else H.id(id);assert(tonumber(id)<=15,"unknown category");publisher=id end
            local p=H.page(request);local sort=request and request.sort or "lastupdate"
            assert(({weekvisit=true,monthvisit=true,weekvote=true,monthvote=true,lastupdate=true,words=true,goodnum=true,postdate=true})[sort],"invalid sort")
            return list(H.get("/wenku/"..sort.."_"..tag.."_"..publisher.."_0_0_0_0_0_"..p.."_0.html",call),p)
        end)
    end
    local function detail(id,call)
        H.id(id)
        if last_detail and last_detail.id==id and ctx.clock.now()-last_detail.time<180 then return H.doc(last_detail.html) end
        local html=H.get("/novel/"..id..".html",call);local doc=H.doc(html)
        assert(meta(doc,"og:novel:book_name"),"missing detail")
        last_detail={id=id,time=ctx.clock.now(),html=html};return doc
    end
    parse_book=function(doc,id)
        local title=meta(doc,"og:novel:book_name");assert(title and title~="","missing title")
        local categories,seen={},{}
        local publisher=meta(doc,"og:novel:category")
        if publisher and publisher~="" then categories[1]=publisher;seen[publisher]=true end
        for _,tag in ipairs(doc:select(".tag-small a")) do local value=H.text(tag);if value~="" and not seen[value] then categories[#categories+1]=value;seen[value]=true end end
        local description=H.text(H.first(doc,"#bookSummary content"))
        if description=="" then description=meta(doc,"og:description") end
        local out={id=id,title=title,author=meta(doc,"og:novel:author"),categories=categories,
            description=description,cover=H.url(meta(doc,"og:image")),metadata={}}
        local status=meta(doc,"og:novel:status")
        if status=="完结" or status=="已完结" or status=="已完成" then out.finished=true
        elseif status=="连载" or status=="连载中" then out.finished=false end
        local updated=meta(doc,"og:novel:update_time")
        if updated then out.updated_at=updated:match("^(%d%d%d%d%-%d%d%-%d%d)") end
        for _,node in ipairs(doc:select(".book-meta")) do
            local text=H.text(node)
            local words=text:match("^([%d%.]+%s*万字)") or text:match("^([%d,]+%s*字)")
            if words then out.metadata.word_count=words;break end
        end
        return out
    end
    function S:getManga(id,call)
        return H.run("getManga",function()return parse_book(detail(id,call),id)end)
    end
    function S:getChapters(id,request,call)
        return H.run("getChapters",function()
            H.firstPage(request);H.id(id)
            local doc=H.doc(H.get("/novel/"..id.."/catalog",call));local items,seen={},{}
            local rows=doc:select(".volume-chapters li")
            if #rows==0 then rows=doc:select("li.jsChapter") end
            local groups,group={},nil
            for _,row in ipairs(rows) do
                local class=" "..H.attr(row,"class").." "
                if class:find(" chapter-bar ",1,true) then
                    group={title=H.text(row),rows={},path=H.attr(H.first(row,"a"),"href")}
                    groups[#groups+1]=group
                elseif class:find(" jsChapter ",1,true) then
                    if not group then group={rows={}};groups[#groups+1]=group end
                    local a=assert(H.first(row,"a"),"missing chapter link")
                    group.rows[#group.rows+1]={title=H.text(a),href=H.attr(a,"href")}
                    if not H.attr(a,"href"):match("^/novel/"..id.."/%d+%.html$") then group.hidden=true end
                end
            end
            local function progress(done)
                if call and call.on_progress then call.on_progress({completed=done,total=#groups})end
            end
            progress(0)
            for group_index,g in ipairs(groups) do
                if g.hidden then
                    -- The site's public volume page often supplies explicit
                    -- links omitted from the aggregate directory. Verify the
                    -- entire sequence against the same volume before using it.
                    if not g.path or not g.path:match("^/novel/"..id.."/vol_%d+%.html$") then H.unsupported("站点未提供完整章节地址，请在原站检查目录") end
                    local volume=H.doc(H.get(g.path,call))
                    local links=volume:select("li.jsChapter a")
                    if #links~=#g.rows then H.unsupported("分卷目录与全书目录不一致，暂不能确认完整章节") end
                    for i,a in ipairs(links) do
                        local href=H.attr(a,"href")
                        local known=g.rows[i].href:match("^/novel/"..id.."/%d+%.html$")
                        if not href:match("^/novel/"..id.."/%d+%.html$")
                            or known and g.rows[i].href~=href or not known and H.text(a)~=g.rows[i].title then
                            H.unsupported("站点未提供可核对的完整分卷目录")
                        end
                        g.rows[i].href=href
                        g.rows[i].title=H.text(a)
                    end
                end
                for _,row in ipairs(g.rows) do
                    local bid,cid=row.href:match("^/novel/(%d+)/(%d+)%.html$")
                    if not cid then H.unsupported("站点隐藏了部分章节地址，当前无法确认完整目录") end
                    assert(bid==id and not seen[cid] and row.title~="","invalid chapter identity");seen[cid]=true
                    items[#items+1]={id=cid,title=g.title and g.title.." · "..row.title or row.title}
                end
                progress(group_index)
            end
            assert(#items>0,"missing catalogue");return {items=items,has_more=false}
        end)
    end
    local function decode(doc,body,cid,call)
        local path
        for _,script in ipairs(doc:select("script")) do
            local url=H.attr(script,"src")
            if url:find("chapterlog.js",1,true) then
                -- The official page also names the .net asset mirror. Fetch
                -- its exact script path through our existing same-origin route.
                url=url:match("^https://www%.bilinovel%.net(/.*)$") or url
                if url:sub(1,#H.base)==H.base then url=url:sub(#H.base+1) end
                assert(url:match("^/themes/zhmb/js/chapterlog%.js%?[%w%.=_%-]+$"),"unknown chapter script origin")
                path=url
            end
        end
        if not path then return body:getcontent() end
        if not script_cache or script_cache.path~=path or ctx.clock.now()-script_cache.time>=300 then
            script_cache={path=path,time=ctx.clock.now(),parameters=D.parameters(H.get(path,call))}
        end
        return D.restore(body,cid,script_cache.parameters)
    end
    function S:getChapterContent(id,cid,call)
        return H.run("getChapterContent",function()
            local path="/novel/"..H.id(id).."/"..H.id(cid)..".html"
            local parts,seen,total={},{},0
            for page=1,64 do
                assert(not seen[path],"chapter pagination loop");seen[path]=true
                local html=H.get(path,call)
                if html:find("內容加載失敗",1,true) or html:find("内容加载失败",1,true) then H.unsupported("站点未返回完整正文，已拦截残缺章节") end
                local book=html:match("articleid:%s*'(%d+)'")
                local chapter=html:match("chapterid:%s*'(%d+)'")
                assert(not book or book==id,"wrong chapter parent");assert(not chapter or chapter==cid,"wrong chapter identity")
                if html:match("chapterisvip:%s*'[1-9]'") then H.unsupported("本章需要站点授权，当前无法读取") end
                local doc=H.doc(html);local body=assert(H.first(doc,"#acontent"),"missing chapter body")
                local content=decode(doc,body,cid,call);total=total+#content;assert(total<=262144,"chapter too large")
                parts[#parts+1]=content
                local next_path=html:match("url_next:%s*'([^']+)'");assert(next_path,"missing pagination data")
                local bid,next_cid,n=next_path:match("^/novel/(%d+)/(%d+)_(%d+)%.html$")
                if bid==id and next_cid==cid then assert(tonumber(n)==page+1,"chapter pages out of order");path=next_path
                else
                    local next_bid=next_path:match("^/novel/(%d+)/")
                    assert(next_bid==id,"unexpected next chapter target")
                    return {format="html",html=table.concat(parts,"\n"),base_url=H.base..path,complete=true}
                end
            end
            error(ctx.error("resource_limit","章节分页超过限额"),0)
        end)
    end
    function S:getImageRequest(resource)return ctx.imageRequest(resource,{Referer=H.base.."/"},20)end
    return S
end
