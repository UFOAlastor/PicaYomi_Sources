-- Public review previews and lazy original-post loading, no write endpoints.
local M={}
function M.new(ctx,H,account)
    local C={}
    local function path(a)
        local href=ctx.text.htmlEntitiesToUtf8(H.attr(a,"href"))
        if href:sub(1,#H.base)==H.base then href=href:sub(#H.base+1) end
        return href
    end
    local function belongs(doc,id)
        for _,a in ipairs(doc:select("a")) do
            local href=path(a)
            if href=="/novel/"..id..".html" or href:match("^/reviews_"..id.."_%d+%.html$") then return true end
        end
        error("wrong review parent")
    end
    function C.list(id,request,call)
        H.id(id);local p=H.page(request)
        local html=H.get("/reviews_"..id.."_"..p..".html",call)
        local doc=H.doc(html);belongs(doc,id)
        local holder=assert(H.first(doc,"#list_content"),"missing review list")
        local items,seen={},{}
        for _,a in ipairs(holder:select("a.book-layout")) do
            local rid=assert(path(a):match("^/reviewshow_(%d+)_1%.html$"),"missing review ID")
            assert(not seen[rid],"duplicate review");seen[rid]=true
            local body=assert(H.first(a,".book-comment-p"),"missing preview")
            local author=H.text(H.first(a,".book-meta-l em"));assert(author~="","missing author")
            local preview=ctx.text.htmlToPlainText(body:getcontent())
            local replies=H.text(H.first(a,".book-meta-r")):match("%d+/(%d+)")
            items[#items+1]={id=rid,content=preview,content_complete=false,author={name=author},
                repliesCount=tonumber(replies) or 0,created_at=H.text(H.first(a,".book-comment-time"))}
        end
        assert(#items>0 or H.text(holder):find("暂无书评",1,true),"unrecognized empty review list")
        -- The site currently comments out its visual pager, but still emits
        -- the server's page links. Parse only that pagination fragment.
        if not H.first(doc,"#pagelink") then
            local pager=html:match('(<div class="pagelink" id="pagelink">.-</div>)')
            if pager then doc=H.doc(pager) end
        end
        return H.paged(doc,p,items,30,function(href)return tonumber(href:match("^/reviews_"..id.."_(%d+)%.html$"))end)
    end
    function C.details(id,rid,call)
        H.id(id);H.id(rid);account.requireLogin()
        local doc=H.doc(H.get("/reviewshow_"..rid.."_1.html",call));belongs(doc,id)
        local body=assert(H.first(doc,".book-comment-p"),"missing original post")
        local row=body.parent
        local author=H.text(H.first(row,".book-meta-l em"));assert(author~="","missing author")
        return {id=rid,content=ctx.text.htmlToPlainText(body:getcontent()),content_complete=true,
            author={name=author},created_at=H.text(H.first(row,".book-comment-time"))}
    end
    return C
end
return M
