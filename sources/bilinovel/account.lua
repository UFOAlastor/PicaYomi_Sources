-- Normal mobile login, verified against the authenticated account page.
-- No shared accounts, password persistence, or cookie import.
local M={}
function M.new(ctx,H)
    local A,state={}
    local function valid(s)
        return type(s)=="table" and type(s.name)=="string" and s.name~=""
            and type(s.cookies)=="table" and next(s.cookies)~=nil
    end
    local function clear()
        assert(ctx.secrets.clear("session"),"session removal failed")
        state=nil;H.cookies={night="0"}
    end
    local function profile(html)
        local doc=H.doc(html)
        local name=H.text(H.first(doc,"span.user-name"))
        assert(name~="" and not H.first(doc,'input[name="password"]'),"missing authenticated profile")
        -- The mobile profile exposes a display name. Never derive a user ID
        -- from that name, an avatar URL, or an opaque cookie.
        return {name=name}
    end
    function A.restore()
        local saved=ctx.secrets.get_json("session")
        state=valid(saved) and saved or nil
        H.cookies=state and state.cookies or {night="0"}
        H.expire=clear;H.logged=A.logged
    end
    function A.logged() return valid(state)==true end
    function A.requireLogin()
        if not A.logged() then H.fail("auth_required","请先登录自己的哔哩轻小说账号") end
    end
    function A.login(username,password,call)
        assert(type(username)=="string" and #username>0 and #username<=256 and type(password)=="string" and #password>0 and #password<=512,"invalid credentials")
        local cookies={night="0"}
        local form=H.doc(H.request("/login.php",call,nil,nil,nil,cookies))
        local f=assert(H.first(form,'form[name="frmlogin"]'),"login form changed")
        assert(H.first(f,'input[name="username"]') and H.first(f,'input[name="password"]'),"login fields changed")
        if H.first(f,'input[name="checkcode"]') then H.unsupported("站点本次要求验证码，当前无法完成登录") end
        local action=H.attr(f,"action")
        if action:sub(1,#H.base)==H.base then action=action:sub(#H.base+1) end
        assert(action:match("^/login%.php%?do=submit") and not action:find("[%c]"),"unknown login target")
        local fields={"username="..H.encode(username),"password="..H.encode(password)}
        local act=false
        for _,input in ipairs(f:select("input")) do
            local name=H.attr(input,"name")
            if H.attr(input,"type")=="hidden" then
                assert(name~="username" and name~="password","duplicate credential field")
                fields[#fields+1]=H.encode(name).."="..H.encode(H.attr(input,"value"))
                if name=="act" and H.attr(input,"value")=="login" then act=true end
            end
        end
        assert(act,"login action changed")
        local html=H.request(action,call,"POST",table.concat(fields,"&"),nil,cookies)
        if html:find("该用户不存在",1,true) then H.fail("auth_required","站点提示账号不存在，请确认登录账号和大小写") end
        if html:find('name="password"',1,true) or html:find("密码错误",1,true) or html:find("密码不正确",1,true) then
            H.fail("auth_required","账号或密码未通过验证，请确认个人账号信息")
        end
        local ok,verified=pcall(profile,H.request("/user.php",call,nil,nil,nil,cookies))
        if not ok then H.fail("auth_required","登录未通过账号页验证，请检查个人账号或站点验证要求") end
        local session={name=verified.name,cookies=cookies}
        assert(valid(session) and ctx.secrets.set_json("session",session),"session persistence failed")
        state=session;H.cookies=cookies
        if H.reset then H.reset() end
        return {success=true}
    end
    function A.logout()clear();if H.reset then H.reset() end;return {success=true}end
    function A.profile(call)
        A.requireLogin()
        local ok,p=pcall(profile,H.get("/user.php",call))
        if not ok then clear();H.fail("auth_expired","哔哩轻小说登录已失效，请重新登录") end
        assert(ctx.secrets.set_json("session",{name=p.name,cookies=H.cookies}),"session persistence failed")
        state.name=p.name;return p
    end
    return A
end
return M
