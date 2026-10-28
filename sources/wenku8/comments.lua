-- Read-only forum adapter. Titles are previews; post bodies are loaded on tap.
local M={}
function M.new(ctx,H)
    local C={}
    local cached={}
    local function path(a)
        local href=ctx.text.htmlEntitiesToUtf8(H.attr(a,"href"))
        if href:sub(1,#H.base)==H.base then href=href:sub(#H.base+1) end
        return href
    end
    local function belongs(doc,id)
        for _,a in ipairs(doc:select("#content a")) do if path(a)=="/book/"..id..".htm" then return true end end
        error("wrong review parent")
    end
    local function paged(doc,p,items)
        return H.paged(doc,p,items,20,function(href)return tonumber(href:match("[?&]page=(%d+)"))end)
    end
    function C.list(id,request,call)
        H.id(id);local p=H.page(request)
        local doc=H.doc(H.get("/modules/article/reviews.php?aid="..id.."&page="..p,call));belongs(doc,id)
        local items,seen={},{}
        for _,row in ipairs(doc:select("#content tr")) do
            local cells=row:select("td")
            if #cells==4 then
                local link=H.first(cells[1],"a")
                local rid=path(link):match("^/modules/article/reviewshow%.php%?rid=(%d+)$")
                if rid then
                    assert(not seen[rid],"duplicate review");seen[rid]=true
                    local author=assert(H.first(cells[3],"a"),"missing review author")
                    local uid=assert(path(author):match("^/userpage%.php%?uid=(%d+)$"),"missing author identity")
                    local replies=assert(tonumber(H.text(cells[2]):match("^(%d+)/%d+$")),"missing reply count")
                    items[#items+1]={id=rid,content=H.text(link),content_complete=false,
                        author={id=uid,name=H.text(author)},repliesCount=replies}
                    -- The table's final column is last-reply time, not post time.
                end
            end
        end
        assert(#items>0 or H.text(doc):find("暂无书评",1,true) or H.text(doc):find("没有书评",1,true)
            or H.first(doc,"table.grid"),"unrecognized review list")
        return paged(doc,p,items)
    end
    local function thread(id,rid,p,call)
        H.id(id);H.id(rid)
        local key=id..":"..rid..":"..p
        local entry=cached[key]
        if entry and ctx.clock.now()-entry.time<60 then return ctx.json.decode(entry.json) end
        local doc=H.doc(H.get("/modules/article/reviewshow.php?rid="..rid.."&page="..p,call));belongs(doc,id)
        local items,root,seen={},nil,{}
        for _,row in ipairs(doc:select("#content tr")) do
            local cells=row:select("td")
            if #cells==2 then
                local anchor
                for _,a in ipairs(cells[2]:select("a")) do if H.attr(a,"name"):match("^yid%d+$") then anchor=a;break end end
                if anchor then
                    local pid=H.attr(anchor,"name"):match("^yid(%d+)$")
                    local floor=assert(tonumber(H.text(anchor):match("^(%d+)#$")),"missing post position")
                    local author=assert(H.first(cells[1],"strong a"),"missing post author")
                    local uid=assert(path(author):match("^/userpage%.php%?uid=(%d+)$"),"missing author identity")
                    local blocks=cells[2]:select("div");assert(#blocks>=3,"missing post body")
                    local content=ctx.text.htmlToPlainText(blocks[#blocks]:getcontent())
                    local item={id=floor==1 and rid or pid,content=content,content_complete=true,
                        author={id=uid,name=H.text(author)},created_at=H.text(blocks[2]):match("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d")}
                    assert(not seen[item.id],"duplicate post");seen[item.id]=true
                    if floor==1 then root=item else items[#items+1]=item end
                end
            end
        end
        assert(p~=1 or root,"missing original post")
        assert(root or #items>0,"missing thread")
        local result=paged(doc,p,items);result.root=root
        local n=0;for k,v in pairs(cached) do n=n+1;if ctx.clock.now()-v.time>=60 then cached[k]=nil end end
        if n>=4 then cached={} end
        cached[key]={time=ctx.clock.now(),json=ctx.json.encode(result)}
        return result
    end
    function C.details(id,rid,call)return assert(thread(id,rid,1,call).root)end
    function C.replies(id,rid,request,call)return thread(id,rid,H.page(request),call)end
    return C
end
return M
