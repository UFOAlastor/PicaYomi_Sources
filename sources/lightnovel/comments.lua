local M={}
function M.new(ctx,H)
    local C={}
    local function comment(v)
        local a=assert(v.author);local content=v.content;assert(type(a)=='table' and type(content)=='string')
        local author_id
        if tostring(a.uid):match('^%d+$') and tonumber(a.uid)>0 then author_id=H.id(a.uid)end
        return {id=H.id(v.comment_id),content=content,content_complete=true,
            author={id=author_id,name=type(a.nickname)=='string' and a.nickname~='' and a.nickname or '未提供昵称',avatar=type(a.avatar)=='string' and a.avatar or nil},
            created_at=type(v.publish_time)=='string' and v.publish_time or nil,
            likesCount=v.stats and v.stats.like_count or v.likeCount or 0,repliesCount=v.reply_count or v.replyCount or 0}
    end
    local function load(bid,cid,r,call)
        local p=H.page(r)
        local d=H.post('new-content-read/get-book-comments',{book_id=H.id(bid),volume_id=0,chapter_id=0,view='',comment_id=cid and H.id(cid) or 0,page=p,pageSize=20,comment_sort='hot',rating_filter='all',include_user_interactions=1},call,{comments=true})
        assert(H.id(d.book_id)==H.id(bid));assert(H.id(d.comment_id==0 and 1 or d.comment_id)==H.id(cid or 1))
        local more,q=H.pagination(d,p,20);local items={}
        for _,v in ipairs(d.list)do items[#items+1]=comment(v)end
        return {items=items,total=q.total,has_more=more,next=more and {page=p+1} or nil},d
    end
    function C.list(bid,r,call)return (load(bid,nil,r,call))end
    function C.replies(bid,cid,r,call)return (load(bid,cid,r,call))end
    function C.details(bid,cid,call)
        local _,d=load(bid,cid,{},call);local v=assert(d.root_comment);assert(H.id(v.comment_id)==H.id(cid));return comment(v)
    end
    return C
end
return M
