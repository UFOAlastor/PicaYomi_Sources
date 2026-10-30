-- First-party web protocol, not a documented public API. No shared accounts.
return function(ctx)
    local H=ctx.require('http').new(ctx)
    local A=ctx.require('account').new(ctx,H)
    local C=ctx.require('comments').new(ctx,H)
    local base,id,page,post,run=H.base,H.id,H.page,H.post,H.run
    local pagination,fail=H.pagination,H.fail
    local S={capabilities={search=true,local_favorites=true,login=true,favorites=true,
        recommendations=true,latest=true,categories=true,rankings=true,comments=true,comment_details=true,download=true},
        replies='paged',access={favorites='login',download='login'}}
    local function book(d)
        assert(type(d.title)=="string" and d.title~="")
        local b={id=id(d.book_id),title=d.title,author=type(d.author_name)=="string" and d.author_name or nil,
            description=type(d.summary)=="string" and d.summary or nil,cover=type(d.cover_url)=="string" and d.cover_url or nil,
            categories={},metadata={},updated_at=type(d.updated_at)=="string" and d.updated_at or nil}
        for _,tag in ipairs(d.tags or {})do if type(tag)=="string"then b.categories[#b.categories+1]=tag end end
        if d.serial_status=="completed" or d.is_completed==1 then b.finished=true
        elseif d.serial_status=="serializing" then b.finished=false end
        if type(d.word_count)=="number" and d.word_count>=0 then b.metadata.word_count=tostring(d.word_count).."字"end
        return b
    end

    local function listing(d,p,size)
        local more,q=pagination(d,p,size);local items={}
        for _,v in ipairs(d.list)do items[#items+1]=book(v)end
        local next_page=more and {page=p+1} or nil
        if next_page and type(d.sequence_id)=='string' and #d.sequence_id>0 and #d.sequence_id<=256 then next_page.sequence_id=d.sequence_id end
        return {items=items,total=q.total,has_more=more,next=next_page}
    end
    function S:init()A.restore();return true,{success=true},nil end
    function S:getSession()return true,{logged_in=A.logged(),cache_scope=A.cacheScope()},nil end
    function S:login(username,password,call)return run('login',function()return A.login(username,password,call)end)end
    function S:logout()return run('logout',A.logout)end
    function S:getUserProfile(call)return run('getUserProfile',function()return A.profile(call)end)end
    local function search(keyword,r,call,extra)
        local p=page(r);assert(type(keyword)=='string' and #keyword<=512)
        local args={q=keyword,scope='',page=p-1,pageSize=20,sort='relevance'}
        for k,v in pairs(extra or {})do args[k]=v end
        return listing(post('bff/apk-search-result-v1',args,call),p,20)
    end
    function S:search(keyword,r,call)return run('search',function()return search(keyword,r,call)end)end
    function S:getRecommendations(r,call)return run('getRecommendations',function()
        local p=page(r);return listing(post('bff/home-promo-v1',{page=p,page_size=20,pageSize=20,sequence_id=r and r.sequence_id},call),p,20)
    end)end
    function S:getLatest(r,call)return run('getLatest',function()
        local p=page(r);return listing(post('bff/home-recent-updates-feed-v1',{page=p-1,page_size=20,pageSize=20,sort='updated'},call),p,20)
    end)end
    function S:getCategories(call)return run('getCategories',function()
        local d=post('bff/apk-search-taxonomy-v1',{},call);assert(type(d.tags)=='table' and type(d.channels)=='table')
        local items={};local seen={}
        for _,tag in ipairs(d.tags)do
            assert(type(tag.name)=='string' and tag.name~='')
            if not seen[tag.name]then items[#items+1]={id='tag:'..tag.name,title=tag.name};seen[tag.name]=true end
        end
        for _,channel in ipairs(d.channels)do
            assert(type(channel.code)=='string' and type(channel.label)=='string')
            items[#items+1]={id='channel:'..channel.code,title=channel.label}
        end
        return items
    end)end
    function S:getCategoryComics(category,r,call)return run('getCategoryComics',function()
        assert(type(category)=='string');local tag=category:match('^tag:(.+)$');local channel=category:match('^channel:([%w_]+)$');assert(tag or channel)
        return search('',r,call,tag and {primary_tag=tag} or {work_type=channel})
    end)end
    function S:getRankingTypes()return true,{{id='weekly_hot',title='周热榜'},{id='daily_fresh',title='新书榜'}},nil end
    function S:getRankings(kind,r,call)return run('getRankings',function()
        assert(kind=='weekly_hot' or kind=='daily_fresh');local p=page(r)
        return listing(post('bff/book-rank-list-v1',{rank_scene=kind,page=p,page_size=20,pageSize=20},call),p,20)
    end)end
    function S:getFavorites(r,call)return run('getFavorites',function()
        A.requireLogin();local p=page(r);local result=listing(post('bff/bookshelf-v1',{page=p,pageSize=20},call),p,20)
        for _,item in ipairs(result.items)do item.favorite=true end
        return result
    end)end
    local function shelf(bid,wanted,call)
        A.requireLogin();bid=id(bid)
        local function state()
            local d=post('new-content-read/get-book-library-state',{book_id=bid},call)
            assert(d.book_id==nil or id(d.book_id)==bid,'wrong shelf identity')
            local v=d.in_shelf;if v==nil then v=d.inShelf end;if v==nil then v=d.has_shelf end;if v==nil then v=d.in_bookshelf end
            assert(v~=nil and (v==1 or v==0 or type(v)=='boolean'),'missing shelf state')
            return v==1 or v==true
        end
        -- A previous mutation may have committed even when its reply was lost.
        -- Reconcile the requested state first; never replay an ambiguous write.
        if state()==wanted then return {success=true}end
        local wrote,result=pcall(post,'new-content-read/toggle-book-shelf',
            {book_id=bid,action=wanted and 'add' or 'remove',source='pc_web'},call)
        if not wrote and (type(result)~='table' or not ({network=true,timeout=true})[result.code])then error(result,0)end
        H.cancel(call)
        local checked,current=pcall(state)
        if checked and current==wanted then return {success=true}end
        if not wrote then error(result,0)end
        if not checked then error(current,0)end
        H.fail('network','收藏状态尚未确认，请稍后重试',true)
    end
    function S:addFavorite(bid,call)return run('addFavorite',function()return shelf(bid,true,call)end)end
    function S:removeFavorite(bid,call)return run('removeFavorite',function()return shelf(bid,false,call)end)end
    function S:getComments(bid,r,call)return run('getComments',function()return C.list(bid,r,call)end)end
    function S:getCommentReplies(bid,cid,r,call)return run('getCommentReplies',function()return C.replies(bid,cid,r,call)end)end
    function S:getCommentDetails(bid,cid,call)return run('getCommentDetails',function()return C.details(bid,cid,call)end)end
    function S:getManga(bid,call)return run('getManga',function()
        bid=id(bid);local d=post('new-content-read/get-book-detail',{book_id=bid,with_volumes=0},call)
        assert(id(d.book_id)==bid);return book(d)
    end)end
    local volume_cache,volume_pages={},{}
    local chapter_pages,chapter_bytes={},0
    local function cachedPage(key)
        for _,entry in ipairs(chapter_pages)do
            if entry.key==key and ctx.clock.now()-entry.time<300 then return ctx.json.decode(entry.raw)end
        end
    end
    local function rememberPage(key,result)
        local raw=ctx.json.encode(result)
        if #raw>128*1024 then return end
        for i=#chapter_pages,1,-1 do
            if chapter_pages[i].key==key then chapter_bytes=chapter_bytes-#chapter_pages[i].raw;table.remove(chapter_pages,i)end
        end
        chapter_pages[#chapter_pages+1]={key=key,time=ctx.clock.now(),raw=raw};chapter_bytes=chapter_bytes+#raw
        while #chapter_pages>128 or chapter_bytes>512*1024 do
            chapter_bytes=chapter_bytes-#chapter_pages[1].raw;table.remove(chapter_pages,1)
        end
    end
    local function getVolumes(bid,vp,call)
        local key=bid..":"..vp
        local cached=volume_cache[key]
        if cached and ctx.clock.now()-cached.time<60 then return cached.data,cached.signature end
        local d=post("new-content-read/get-book-volumes",{book_id=bid,page=vp,pageSize=50,page_size=50},call)
        assert(id(d.book_id)==bid);local _,paging=pagination(d,vp,50)
        local compact={book_id=bid,pagination=paging,list={}};local revision={}
        for i,v in ipairs(d.list)do
            local vid=id(v.volume_id);assert(type(v.title)=='string')
            compact.list[i]={volume_id=vid,title=v.title}
            revision[i]={vid,v.title,v.chapter_count or '',v.updated_at or '',v.first_chapter_id or '',
                v.last_chapter_id or '',v.status or '',v.is_locked or ''}
        end
        local signature=ctx.hashes.sha256(ctx.json.encode(revision))
        -- The upstream repeats large introductions and poster profiles on each
        -- volume. Retain only directory fields, bounded to four small pages.
        if #ctx.json.encode(compact)<=128*1024 then
            if not volume_cache[key]then volume_pages[#volume_pages+1]=key end
            volume_cache[key]={data=compact,time=ctx.clock.now(),signature=signature}
            while #volume_pages>4 do volume_cache[table.remove(volume_pages,1)]=nil end
        end
        return compact,signature
    end
    H.invalidate=function()volume_cache={};volume_pages={};chapter_pages={};chapter_bytes=0 end
    -- Return volume continuation through the host; never publish a partial book.
    function S:getChapters(bid,r,call)return run("getChapters",function()
        if call and call.force_refresh and next(r or {})==nil then H.invalidate()end
        bid=id(bid);local vp=r and r.volume_page or 1;local vi=r and r.volume_index or 1;local cp=page(r)
        assert(type(vp)=="number" and vp>=1 and vp%1==0 and vp<=200)
        assert(type(vi)=="number" and vi>=1 and vi%1==0 and vi<=50)
        local volumes,signature=getVolumes(bid,vp,call)
        assert(id(volumes.book_id)==bid);local vm,volume_paging=pagination(volumes,vp,50)
        if #volumes.list==0 then assert(vp==1 and not vm);return {items={},has_more=false}end
        local function key(volume,p)return bid..':'..id(volume.volume_id)..':'..p..':'..signature end
        local function fetch(volume,index,p)
            local vid=id(volume.volume_id)
            local d=post('new-content-read/get-volume-chapters',{book_id=bid,volume_id=vid,page=p,pageSize=50,page_size=50},call)
            assert(id(d.book_id)==bid and id(d.volume_id)==vid);local more=pagination(d,p,50)
            local items={}
            for _,c in ipairs(d.list)do
                assert(id(c.book_id)==bid and id(c.volume_id)==vid and type(c.title)=='string')
                items[#items+1]={id=id(c.chapter_id),title=tostring(volume.title)..' · '..c.title}
            end
            local next_page
            if more then next_page={volume_page=vp,volume_index=index,page=p+1}
            elseif index<#volumes.list then next_page={volume_page=vp,volume_index=index+1,page=1}
            elseif vm then next_page={volume_page=vp+1,volume_index=1,page=1}end
            local result={items=items,has_more=next_page~=nil,next=next_page}
            H.cancel(call)
            if call and call.directory_request then rememberPage(key(volume,p),result)end
            return result
        end
        if call and call.directory_request and vi==1 and cp==1 and ctx.tasks then
            local jobs={};local done=0
            for index,volume in ipairs(volumes.list)do
                if not cachedPage(key(volume,1))then
                    jobs[#jobs+1]=function()
                        fetch(volume,index,1);done=done+1
                        if call.on_progress then call.on_progress({
                            message='正在获取并核对卷目录…',completed=(vp-1)*50+done,
                            total=volume_paging.total})end
                    end
                else done=done+1 end
            end
            ctx.tasks.map(jobs,3)
        end
        local volume=assert(volumes.list[vi]);local cache_key=key(volume,cp)
        if call and call.directory_request then
            local saved=cachedPage(cache_key)
            if saved then H.cancel(call);return saved end
        end
        return fetch(volume,vi,cp)
    end)end

    function S:getChapterContent(bid,cid,call)return run('getChapterContent',function()
        bid=id(bid);cid=id(cid)
        assert(call and (call.purpose=='reading' or call.purpose=='download'),'host must identify reading/download purpose')
        if call.purpose=='download' then
            A.requireLogin();local access=post('new-content-read/check-book-download-access',{book_id=bid},call)
            if access.allow~=true and access.allow~=1 then fail('auth_required','站点未允许下载本书，请在网页确认下载权限')end
        end
        local d=post('new-content-read/get-chapter-detail',{book_id=bid,chapter_id=cid},call)
        assert(id(d.book_id)==bid and id(d.chapter_id)==cid)
        if d.locked~=0 or d.unlocked~=1 then fail('auth_required','本章需要站点授权，请在网页确认阅读权限')end
        local html=type(d.body_snapshot)=='table' and d.body_snapshot.body_html
        assert(type(html)=='string' and #html>0 and #html<=262144,'missing full body')
        return {format='html',html=html,base_url=base..'/reader/'..bid..'/'..cid,complete=true}
    end)end
    function S:getImageRequest(resource)return ctx.imageRequest(resource,{Referer=base..'/'},20)end
    return S
end
