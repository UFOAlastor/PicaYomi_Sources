local M={}
function M.new(ctx,H)
    local A,state={}
    local function valid(v)return type(v)=='table' and type(v.uid)=='string' and v.uid:match('^%d+$') and type(v.key)=='string' and #v.key>0 and #v.key<=4096 end
    local function clear()
        assert(ctx.secrets.clear('session'),'session removal failed');state=nil
        if H.invalidate then H.invalidate()end
    end
    local function decode(d)
        local a=assert(d.auth);local u=assert(d.user)
        local uid=H.id(a.uid);assert(H.id(u.uid or u.id)==uid,'account identity mismatch')
        local key=a.security_key;assert(type(key)=='string' and key~='' and #key<=4096)
        local name=u.nickname or u.username or u.name;assert(type(name)=='string' and name~='')
        return {uid=uid,key=key,profile={_id=uid,name=name,avatar=type(u.avatar or u.avatar_url)=='string' and (u.avatar or u.avatar_url) or nil}}
    end
    function A.restore()
        local v=ctx.secrets.get_json('session');state=valid(v) and v or nil
        H.token=function()return state and state.key end;H.expire=clear
    end
    function A.logged()return valid(state)==true end
    function A.cacheScope()
        if A.logged()then return ctx.hashes.sha256(state.uid..'\0'..state.key)end
    end
    function A.requireLogin()if not A.logged()then H.fail('auth_required','请先登录自己的轻之国度账号')end end
    function A.login(username,password,call)
        assert(type(username)=='string' and #username>0 and #username<=256 and type(password)=='string' and #password>0 and #password<=512)
        local d=H.post('bff/auth-password-login-v1',{username=username,password=password},call,{anonymous=true,login=true})
        H.cancel(call);local next_state=decode(d)
        assert(ctx.secrets.set_json('session',next_state),'session persistence failed')
        state=next_state;if H.invalidate then H.invalidate()end
        return {success=true}
    end
    function A.profile(call)
        A.requireLogin();local uid=state.uid
        local d=H.post('bff/auth-session-v1',{},call)
        if d.logged_in~=1 and d.logged_in~=true then clear();H.fail('auth_expired','轻之国度登录已失效，请重新登录')end
        local valid,current=pcall(decode,d)
        if not valid or current.uid~=uid then clear();H.fail('auth_expired','账号身份已改变，请重新登录')end
        return current.profile
    end
    function A.logout()clear();return {success=true}end
    return A
end
return M
