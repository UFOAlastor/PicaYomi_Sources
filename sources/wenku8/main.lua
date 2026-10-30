return function(ctx)
    local H=ctx.require("html").new(ctx)
    local account=ctx.require("account").new(ctx,H)
    local comments=ctx.require("comments").new(ctx,H)
    local favorite_cache,favorite_pages,favoriteState
    local S={capabilities={recommendations=true,latest=true,search=true,categories=true,
        login=true,favorites=true,local_favorites=true,download=true,comments=true,comment_details=true,replies="paged"},
        access={recommendations="login",latest="login",search="login",favorites="login"}}
    function S:init() account.restore();return true,{success=true},nil end
    function S:getSession()return true,{logged_in=account.logged()},nil end
    function S:login(username,password,call)favorite_cache=nil;favorite_pages=nil;return H.run("login",account.login,username,password,call)end
    function S:logout()favorite_cache=nil;favorite_pages=nil;return H.run("logout",account.logout)end
    function S:getUserProfile(call)return H.run("getUserProfile",account.profile,call)end
    function S:getComments(id,request,call)return H.run("getComments",comments.list,id,request,call)end
    function S:getCommentDetails(id,rid,call)return H.run("getCommentDetails",comments.details,id,rid,call)end
    function S:getCommentReplies(id,rid,request,call)return H.run("getCommentReplies",comments.replies,id,rid,request,call)end
    local function page(doc,current,items)
        return H.paged(doc,current,items,20,function(href)return tonumber(href:match("[?&]page=(%d+)"))end)
    end
    local function cards(html,current)
        local doc=H.doc(html);local items,seen={},{}
        for _,image in ipairs(doc:select('#content img')) do
            local url=H.attr(image,"src")
            local id=url:match("/image/%d+/(%d+)/%d+[a-z]?%.jpg$")
            if id and not seen[id] then
                local holder=image.parent
                local a,depth
                depth=0
                while holder and holder~=doc and depth<8 do
                    for _,link in ipairs(holder:select("a")) do
                        local href=H.attr(link,"href")
                        if href:match("/book/"..id.."%.htm$") and H.text(link)~="" then a=link;break end
                    end
                    if a then break end
                    holder=holder.parent;depth=depth+1
                end
                -- Image-only recommendation cards may use the link's title.
                local image_link=image.parent
                local image_title=image_link and H.attr(image_link,"title") or ""
                if not a and image_title~="" then a=image_link;holder=image_link end
                if a then
                    seen[id]=true
                    local text=H.text(holder)
                    local author=text:match("作者[：:]%s*([^/%s]+)")
                    items[#items+1]={id=id,title=H.text(a)~="" and H.text(a) or image_title,cover=H.url(url),author=author}
                end
            end
        end
        if #items==0 then
            local id
            for _,a in ipairs(doc:select("fieldset a")) do id=H.attr(a,"href"):match("^/novel/%d+/(%d+)/index%.htm$");if id then break end end
            local title=H.text(H.first(doc,"#content span b"))
            if id and title~="" then items[1]={id=id,title=title,cover=H.url(H.attr(H.first(doc,"#content img"),"src"))}
            else assert(H.text(doc):find("没有找到",1,true) or H.text(doc):find("无相关",1,true),"unrecognized empty list") end
        end
        return page(doc,current,items)
    end
    local sorts={{id="allvisit",title="人气"},{id="allvote",title="推荐"},{id="lastupdate",title="最近更新"}}
    function S:getSortOptions(kind)return true,kind=="latest" and {sorts[3],sorts[1],sorts[2]} or kind=="recommend" and sorts or {},nil end
    local function listSort(request,default)
        local sort=request and request.sort or default
        assert(({allvisit=true,allvote=true,lastupdate=true})[sort],"invalid sort")
        return sort
    end
    function S:getRecommendations(request,call)
        return H.run("getRecommendations",function()
            account.requireLogin();local p=H.page(request)
            return cards(H.get("/modules/article/toplist.php?sort="..listSort(request,"allvisit").."&page="..p,call),p)
        end)
    end
    function S:getLatest(request,call)
        return H.run("getLatest",function()
            account.requireLogin();local p=H.page(request)
            return cards(H.get("/modules/article/toplist.php?sort="..listSort(request,"lastupdate").."&page="..p,call),p)
        end)
    end
    function S:search(keyword,request,call)
        return H.run("search",function()
            account.requireLogin();assert(type(keyword)=="string" and #keyword>0 and #keyword<=512,"invalid search")
            local p=H.page(request)
            return cards(H.get("/modules/article/search.php?searchtype=articlename&searchkey="..H.query(keyword).."&page="..p,call),p)
        end)
    end
    local categories={{id="1",title="电击文库"},{id="2",title="富士见文库"},{id="3",title="角川文库"},
        {id="4",title="MF文库J"},{id="5",title="Fami通文库"},{id="6",title="GA文库"},
        {id="7",title="HJ文库"},{id="8",title="一迅社文库"},{id="9",title="集英社"},
        {id="10",title="小学馆"},{id="11",title="讲谈社"},{id="12",title="其他文库"}}
    -- Verified site topic catalogue (2026-10-27); keeping the picker offline.
    local topics={
        {id="tag:校园",title="校园"},
        {id="tag:青春",title="青春"},
        {id="tag:恋爱",title="恋爱"},
        {id="tag:治愈",title="治愈"},
        {id="tag:群像",title="群像"},
        {id="tag:竞技",title="竞技"},
        {id="tag:音乐",title="音乐"},
        {id="tag:美食",title="美食"},
        {id="tag:旅行",title="旅行"},
        {id="tag:欢乐向",title="欢乐向"},
        {id="tag:经营",title="经营"},
        {id="tag:职场",title="职场"},
        {id="tag:斗智",title="斗智"},
        {id="tag:脑洞",title="脑洞"},
        {id="tag:宅文化",title="宅文化"},
        {id="tag:穿越",title="穿越"},
        {id="tag:奇幻",title="奇幻"},
        {id="tag:魔法",title="魔法"},
        {id="tag:异能",title="异能"},
        {id="tag:战斗",title="战斗"},
        {id="tag:科幻",title="科幻"},
        {id="tag:机战",title="机战"},
        {id="tag:战争",title="战争"},
        {id="tag:冒险",title="冒险"},
        {id="tag:龙傲天",title="龙傲天"},
        {id="tag:悬疑",title="悬疑"},
        {id="tag:犯罪",title="犯罪"},
        {id="tag:复仇",title="复仇"},
        {id="tag:黑暗",title="黑暗"},
        {id="tag:猎奇",title="猎奇"},
        {id="tag:惊悚",title="惊悚"},
        {id="tag:间谍",title="间谍"},
        {id="tag:末日",title="末日"},
        {id="tag:游戏",title="游戏"},
        {id="tag:大逃杀",title="大逃杀"},
        {id="tag:青梅竹马",title="青梅竹马"},
        {id="tag:妹妹",title="妹妹"},
        {id="tag:女儿",title="女儿"},
        {id="tag:JK",title="JK"},
        {id="tag:JC",title="JC"},
        {id="tag:大小姐",title="大小姐"},
        {id="tag:性转",title="性转"},
        {id="tag:伪娘",title="伪娘"},
        {id="tag:人外",title="人外"},
        {id="tag:后宫",title="后宫"},
        {id="tag:百合",title="百合"},
        {id="tag:耽美",title="耽美"},
        {id="tag:NTR",title="NTR"},
        {id="tag:女性视角",title="女性视角"},
    }
    local topic_ids={}
    for _,topic in ipairs(topics)do topic_ids[topic.id]=true end
    function S:getCategories()
        local out=ctx.json.decode(ctx.json.encode(topics))
        for _,category in ipairs(categories)do out[#out+1]=ctx.json.decode(ctx.json.encode(category)) end
        return true,out,nil
    end
    function S:getCategoryComics(id,request,call)
        return H.run("getCategoryComics",function()
            account.requireLogin()
            local p=H.page(request)
            if topic_ids[id] then
                return cards(H.get("/modules/article/tags.php?t="..H.query(id:sub(5)).."&page="..p,call),p)
            end
            H.id(id);assert(tonumber(id)>=1 and tonumber(id)<=#categories,"unknown publisher")
            return cards(H.get("/modules/article/articlelist.php?class="..id.."&page="..p,call),p)
        end)
    end
    function S:getManga(id,call)
        return H.run("getManga",function()
            local doc=H.doc(H.get("/book/"..H.id(id)..".htm",call))
            local title=H.text(H.first(doc,"#content span b"));assert(title~="","missing title")
            local out={id=id,title=title,categories={},metadata={},cover=H.url(H.attr(H.first(doc,"#content img"),"src"))}
            for _,td in ipairs(doc:select("#content td")) do
                local t=H.text(td)
                if t:sub(1,#"小说作者：")=="小说作者：" then out.author=t:sub(#"小说作者："+1) end
                if t:sub(1,#"文库分类：")=="文库分类：" then out.categories[#out.categories+1]=t:sub(#"文库分类："+1) end
                if t:sub(1,#"文章状态：")=="文章状态：" then
                    local status=t:sub(#"文章状态："+1)
                    if status=="已完成" or status=="已完结" then out.finished=true
                    elseif status=="连载中" or status=="连载" then out.finished=false end
                end
                local date=t:match("^最后更新：%s*(%d%d%d%d%-%d%d%-%d%d)")
                if date then out.updated_at=date end
                local words=t:match("^全文长度：%s*([%d,]+)字$")
                if words then out.metadata.word_count=words.."字" end
            end
            local description_next=false
            for _,span in ipairs(doc:select("#content span")) do
                local t=H.text(span)
                if t:sub(1,#"作品Tags：")=="作品Tags：" then
                    for tag in t:sub(#"作品Tags："+1):gmatch("%S+") do out.categories[#out.categories+1]=tag end
                end
                if description_next then out.description=t;break end
                if t=="内容简介：" then description_next=true end
            end
            assert(out.author and out.author~="" and #out.categories>0,"missing metadata")
            if account.logged() then
                local ok,favorite=pcall(favoriteState,id,call)
                -- Optional shelf status must not discard valid book metadata
                -- when the shelf is rate limited. Unknown stays absent.
                if ok then out.favorite=favorite end
            end
            return out
        end)
    end
    function S:getChapters(id,request,call)
        return H.run("getChapters",function()
            H.id(id);assert(H.page(request)==1,"directory is a complete page")
            local path="/novel/"..math.floor(tonumber(id)/1000).."/"..id.."/index.htm"
            local doc=H.doc(H.get(path,call));local items,seen={},{};local volume
            for _,td in ipairs(doc:select("td")) do
                if H.attr(td,"class")=="vcss" then volume=H.text(td)
                else
                    for _,a in ipairs(td:select("a")) do
                        local cid=H.attr(a,"href"):match("^(%d+)%.htm$")
                        if cid then
                            assert(volume and volume~="" and not seen[cid],"invalid chapter identity")
                            seen[cid]=true;items[#items+1]={id=cid,title=volume.." · "..H.text(a)}
                        end
                    end
                end
            end
            assert(#items>0,"missing directory");return {items=items,has_more=false}
        end)
    end
    function S:getChapterContent(id,cid,call)
        return H.run("getChapterContent",function()
            local path="/novel/"..math.floor(tonumber(H.id(id))/1000).."/"..id.."/"..H.id(cid)..".htm"
            local html=H.get(path,call)
            if html:find("因版权问题",1,true) or html:find("版权方要求",1,true) then H.fail("unsupported","本站已因版权限制停止提供本章正文") end
            local doc=H.doc(html);local content=assert(H.first(doc,"#content"),"missing text")
            assert(H.text(H.first(doc,"#title"))~="" and H.first(doc,"#foottext"),"incomplete chapter")
            local plain=H.text(content)
            assert(plain~="" or H.first(content,"img"),"empty chapter")
            local html=content:getcontent():gsub("(<[iI][mM][gG][^>]-[sS][rR][cC]%s*=%s*[\"'])http://","%1https://")
            return {format="html",html=html,base_url=H.base..path,complete=true}
        end)
    end
    local function shelf(html,current)
        local doc=H.doc(html);local items,seen,records={},{},{}
        for _,a in ipairs(doc:select("a")) do
            local href=ctx.text.htmlEntitiesToUtf8(H.attr(a,"href"))
            if href:sub(1,#H.base)==H.base then href=href:sub(#H.base+1) end
            local id=href:match("[?&]aid=(%d+)")
            if href:match("^/modules/article/readbookcase%.php%?") and id and not seen[id] then
                local record=href:match("[?&]bid=(%d+)")
                assert(record,"missing collection record identity")
                seen[id]=true;records[id]=record;items[#items+1]={id=id,title=H.text(a),favorite=true}
            end
        end
        if #items==0 then
            assert(H.first(doc,'form[name="checkform"]') and (H.text(doc):find("书架",1,true) or H.text(doc):find("收藏",1,true)),"unrecognized empty shelf")
        end
        return page(doc,current,items),records
    end
    function S:getFavorites(request,call)
        return H.run("getFavorites",function()
            account.profile(call);local p=H.page(request)
            local function fetch(n)return shelf(H.get('/modules/article/bookcase.php?page='..n,call),n)end
            if p==1 or not favorite_pages or ctx.clock.now()-favorite_pages.time>=60 then
                local first,records=fetch(1)
                local last,tail=first,nil
                -- Usually the server gives an explicit last-page link. For a
                -- short pager, follow only its actual continuation to prove it.
                for _=1,200 do
                    if last.pagination then break end
                    assert(last.has_more and last.next,'missing shelf continuation')
                    local n=H.page(last.next)
                    last=fetch(n);tail={page=n,result=last}
                end
                assert(last.pagination,'shelf end was not confirmed')
                favorite_pages={time=ctx.clock.now(),pages=last.pagination.pages,
                    first=first,records=records,tail=tail}
            end
            local pages=favorite_pages.pages
            assert(p<=pages,'shelf page outside confirmed range')
            local physical=pages-p+1
            local result,records
            if physical==1 then result,records=favorite_pages.first,favorite_pages.records
            elseif favorite_pages.tail and favorite_pages.tail.page==physical then result=favorite_pages.tail.result
            else result,records=fetch(physical)end
            if result.pagination and result.pagination.pages~=pages then
                favorite_pages=nil;H.fail('invalid_response','书架分页已变化，请返回第一页刷新',true)
            end
            local items={}
            for i=#result.items,1,-1 do items[#items+1]=result.items[i]end
            result={items=items,has_more=p<pages,next=p<pages and {page=p+1} or nil,
                pagination={mode='page',page=p,pages=pages,page_size=math.max(20,#items)}}
            if p==1 and not result.has_more then
                local ids={};for _,item in ipairs(result.items) do ids[item.id]=true end
                favorite_cache={time=ctx.clock.now(),ids=ids,records=records,pages={}}
                for id in pairs(records) do favorite_cache.pages[id]=1 end
            end
            return result
        end)
    end
    favoriteState=function(id,call)
        if not favorite_cache or ctx.clock.now()-favorite_cache.time>=60 then
            local ids,records,pages,complete={},{},{},false
            for p=1,10 do
                local result,page_records=shelf(H.get("/modules/article/bookcase.php?page="..p,call),p)
                for _,item in ipairs(result.items) do ids[item.id]=true;records[item.id]=page_records[item.id];pages[item.id]=p end
                if not result.has_more then complete=true;break end
            end
            assert(complete,"shelf exceeds scan limit")
            favorite_cache={time=ctx.clock.now(),ids=ids,records=records,pages=pages}
        end
        return favorite_cache.ids[id]==true
    end
    function S:addFavorite(id,call)
        return H.run("addFavorite",function()
            account.profile(call);favorite_cache=nil;favorite_pages=nil
            local html=H.get("/modules/article/addbookcase.php?bid="..H.id(id),call)
            assert(html:find("成功",1,true) or html:find("已经",1,true),"collection was not confirmed")
            assert(favoriteState(id,call),"collection addition was not confirmed")
            return {success=true}
        end)
    end
    function S:removeFavorite(id,call)
        return H.run("removeFavorite",function()
            account.profile(call);H.id(id)
            local record,found_page
            if favorite_cache and ctx.clock.now()-favorite_cache.time<60 then
                record,found_page=favorite_cache.records[id],favorite_cache.pages[id]
            end
            for p=1,record and 0 or 10 do
                local result,records=shelf(H.get("/modules/article/bookcase.php?page="..p,call),p)
                record=records[id]
                if record then found_page=p;break end
                if not result.has_more then break end
            end
            if not record then H.fail("not_found","当前书架没有这本小说；未执行删除") end
            assert(record:match("^%d+$"),"invalid collection record identity")
            favorite_cache=nil;favorite_pages=nil
            local result=H.get("/modules/article/bookcase.php?page="..found_page.."&delid="..record,call)
            assert(not result:find("错误原因",1,true),"collection deletion failed")
            -- The delete response is the server-rendered resulting shelf.
            -- Verify that page directly, rather than immediately fetching it again.
            local _,remaining=shelf(result,found_page)
            assert(not remaining[id],"collection deletion was not confirmed")
            return {success=true}
        end)
    end
    function S:getImageRequest(resource)return ctx.imageRequest(resource,{Referer=H.base.."/"},20)end
    return S
end
