-- Personal account only. Never import cookies or credentials from another app.
local A={}
function A.new(ctx,H)
    local state,verified_profile,verified_at
    local self={}
    local function valid(s)
        return type(s)=="table" and type(s.uid)=="string" and s.uid:match("^%d+$") and tonumber(s.uid)>0
            and type(s.cookies)=="table" and next(s.cookies)~=nil
    end
    local function clear()
        assert(ctx.secrets.clear("session"),"session removal failed")
        state=nil;H.cookies={};verified_profile=nil;verified_at=nil
    end
    local function profile(html)
        local doc=H.doc(html)
        local id,name
        for _,tr in ipairs(doc:select("tr")) do
            local cells=tr:select("td")
            if #cells>=2 then
                local label,value=H.text(cells[1]),H.text(cells[2])
                if label=="用户ID：" or label=="用户ID:" then id=value:match("^(%d+)$") end
                if label=="用户名：" or label=="用户名:" then name=value end
            end
        end
        assert(id and tonumber(id)>0 and name and name~="","missing verified account identity")
        return {_id=id,name=name}
    end
    local function save(s)
        assert(valid(s),"invalid personal session")
        assert(ctx.secrets.set_json("session",s),"session persistence failed")
        state=s;H.cookies=s.cookies
    end
    function self.restore()
        local saved=ctx.secrets.get_json("session")
        state=valid(saved) and saved or nil
        H.cookies=state and state.cookies or {}
        H.expire=clear
    end
    function self.logged() return valid(state)==true end
    function self.requireLogin()
        if not self.logged() then H.fail("auth_required","请先登录自己的轻小说文库账号") end
    end
    function self.login(username,password,call)
        assert(type(username)=="string" and #username>0 and #username<=256 and type(password)=="string" and #password>0 and #password<=512,"invalid credentials")
        local cookies={}
        local form=H.doc(H.request("/login.php",call,nil,nil,cookies))
        assert(H.first(form,'input[name="username"]') and H.first(form,'input[name="password"]'),"login form changed")
        if H.first(form,'input[name="checkcode"]') then H.fail("unsupported","站点本次要求验证码，当前无法完成登录") end
        local body="username="..H.query(username).."&password="..H.query(password).."&usecookie=31536000&action=login&submit="..H.query("登 录")
        local html=H.request("/login.php",call,"POST",body,cookies)
        if not html:find("登录成功",1,true) then
            if html:find("验证码",1,true) then H.fail("unsupported","站点本次要求验证码，当前无法完成登录") end
            H.fail("auth_required","账号或密码未通过验证，请确认个人账号信息")
        end
        local verified=profile(H.request("/userdetail.php?charset=gbk",call,nil,nil,cookies))
        save{uid=verified._id,name=verified.name,cookies=cookies}
        verified_profile,verified_at=verified,ctx.clock.now()
        return {success=true}
    end
    function self.logout() clear();return {success=true} end
    function self.profile(call)
        self.requireLogin()
        if verified_profile and ctx.clock.now()-verified_at<30 then
            return ctx.json.decode(ctx.json.encode(verified_profile))
        end
        local html=H.get("/userdetail.php?charset=gbk",call)
        local ok,value=pcall(profile,html)
        if not ok or value._id~=state.uid then clear();H.fail("auth_expired","轻小说文库登录已失效，请重新登录") end
        verified_profile,verified_at=value,ctx.clock.now()
        return value
    end
    return self
end
return A
