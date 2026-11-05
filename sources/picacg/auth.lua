local ctx = assert(ctx, "source SDK context required")
-- source/picacg/auth.lua
-- 源 A 认证模块
-- 从 api/auth.lua 迁移

local logger = ctx.logger
local SecretStore = ctx.secrets
local json = ctx.json

local PicacgAuth = {}

-- 配置键前缀
local CONFIG_PREFIX = "source.picacg"
local TOKEN_KEY = CONFIG_PREFIX .. ".token"
local USERNAME_KEY = CONFIG_PREFIX .. ".username"
local PASSWORD_KEY = CONFIG_PREFIX .. ".password"
local function clear_favorites()
    if ctx.cache and ctx.cache.clearPattern then ctx.cache:clearPattern("picacg_favs_")end
end

--- 获取 Token (加密存储; 兼容旧明文的 key)
function PicacgAuth:getToken()
    local token = SecretStore.get(TOKEN_KEY)
    if token and token ~= "" then
        return token
    end
    -- 兼容旧格式 ("token" 明文键由 SecretStore 就地迁移)
    return SecretStore.get("token")
end

--- 设置 Token
function PicacgAuth:setToken(token, internal)
    if not internal then
        self._epoch=(self._epoch or 0)+1;self._refreshing=nil
        SecretStore.clear(PASSWORD_KEY)
    end
    self._expired=false
    clear_favorites()
    if token == nil or token == "" then
        SecretStore.clear(TOKEN_KEY)
        SecretStore.clear("token")
        return
    end
    SecretStore.set(TOKEN_KEY, token)
    -- 新版本只写一个键; 旧明文键必须清掉, 否则迁移逻辑会再次见到它
    SecretStore.clear("token")
end

function PicacgAuth:expire()self._expired=true;clear_favorites()end

--- 是否已登录
function PicacgAuth:isLoggedIn()
    return not self._expired and self:getToken() ~= nil
end

--- 登录
-- @param username: 用户名/邮箱
-- @param password: 密码
-- @param http_client: HttpClient 实例
-- @param headers: Headers 模块
-- @return: true 或 nil, err
function PicacgAuth:login(username, password, http_client, headers, recovery)
    if not username or not password then
        return nil, "用户名和密码不能为空"
    end
    if not recovery then
        self._epoch=(self._epoch or 0)+1;self._refreshing=nil;self._recover_after=nil
    end
    local epoch=self._epoch or 0

    local body = json.encode({
        email = username,
        password = password,
    })

    local path = "auth/sign-in"
    local url = headers:buildUrl(path)
    local req_headers = headers:build(path, "POST", nil)

    if not req_headers then
        return nil, "请求头构造失败"
    end

    if logger.enabled then logger.info("Picayomi SourceAAuth: 登录请求") end

    local send=recovery and http_client.request or http_client.requestWithRetry
    local response, err = send(http_client,"POST", url, req_headers, body, 15)
    if epoch~=(self._epoch or 0) or recovery and self._refreshing~=recovery then
        return nil,"登录状态已改变，请重试"
    end
    if not response then
        return nil, "网络请求失败: " .. tostring(err)
    end

    local data = http_client:parseJsonResponse(response)
    if not data then
        return nil, "响应解析失败"
    end

    if data.code == 200 and data.message == "success" then
        local token = data.data and data.data.token
        if token and token ~= "" then
            self:setToken(token,true)
            -- 账号名也是 PII, 不写明文
            SecretStore.clear(PASSWORD_KEY)
            if SecretStore.set(USERNAME_KEY, username) and not ctx.accountRecoveryManaged then SecretStore.set(PASSWORD_KEY, password) end
            if logger.enabled then logger.info("Picayomi SourceAAuth: 登录成功") end
            return true
        end
    end

    local msg = data.message or "登录失败"
    if recovery and (tonumber(response.status_code)==401 or tonumber(data.code)==401 or tonumber(data.code)==400) then
        SecretStore.clear(PASSWORD_KEY);self:expire()
        return nil,"自动登录失败，请重新登录并输入账号密码"
    end
    if ctx.accountRecoveryManaged and (tonumber(data.code)==400 or tonumber(data.code)==401) then
        return nil,ctx.error("auth_required","账号或密码已失效，请重新登录")
    end
    logger.err("Picayomi SourceAAuth: 登录失败: " .. msg)
    return nil, msg
end

-- One bounded sign-in per expired session; never login for an ordinary network error.
function PicacgAuth:recover(http_client,headers,failed_token,epoch)
    if epoch~=(self._epoch or 0) then return nil,"登录状态已改变，请重试" end
    if not self._expired and self:getToken()~=failed_token then return true end
    local now=ctx.clock.now()
    if self._refreshing and now<self._refreshing.until_at then
        return nil,"正在恢复登录，请稍后重试"
    end
    if self._recover_after and now<self._recover_after then return nil,"恢复登录暂未成功，请稍后重试" end
    local username,password=SecretStore.get(USERNAME_KEY),SecretStore.get(PASSWORD_KEY)
    if not username or username=='' or not password or password=='' then
        self:expire();return nil,"登录状态已失效，请重新登录"
    end
    local attempt={until_at=now+30};self._refreshing=attempt;self._recover_after=now+30
    local called,ok,err=pcall(self.login,self,username,password,http_client,headers,attempt)
    if self._refreshing==attempt then self._refreshing=nil end
    if not called then error(ok,0)end
    return ok,err
end

--- 退出登录
function PicacgAuth:logout()
    self._epoch=(self._epoch or 0)+1;self._refreshing=nil;self._recover_after=nil
    self._expired=true;clear_favorites()
    SecretStore.clear(TOKEN_KEY)
    SecretStore.clear("token")
    SecretStore.clear(USERNAME_KEY)
    SecretStore.clear(PASSWORD_KEY)
    if logger.enabled then logger.info("Picayomi SourceAAuth: 已退出登录") end
end

--- 获取用户信息
function PicacgAuth:getUserProfile(http_client, headers, recovered)
    local epoch=self._epoch or 0
    local token = self:getToken()
    if not token then
        return nil, "未登录"
    end

    local path = "users/profile"
    local url = headers:buildUrl(path)
    local req_headers = headers:build(path, "GET", token)

    local response, err = http_client:get(url, req_headers, 10)
    if not response then
        return nil, "网络请求失败: " .. tostring(err)
    end

    local data = http_client:parseJsonResponse(response)
    if epoch~=(self._epoch or 0) then return nil,"登录状态已改变，请重试" end
    if tonumber(response.status_code)==401 or data and tonumber(data.code)==401 then
        if not recovered and not ctx.accountRecoveryManaged then
            local ok,err=self:recover(http_client,headers,token,epoch)
            if ok then return self:getUserProfile(http_client,headers,true)end
            return nil,err
        end
        self:expire();return nil,"登录状态已失效，请重新登录"
    end
    if not data then
        return nil, "响应解析失败"
    end

    if data.code == 200 and data.data and data.data.user then
        local user = data.data.user

        -- 规范化用户资料, 统一各源的 profile 字段
        local profile = {
            id = user._id or "unknown_id",
            name = user.name or "未知用户",
            email = user.email or "",
            level = tonumber(user.level) or 1,
            exp = tonumber(user.exp) or 0,
            title = user.title or "",
            slogan = user.slogan or "",
            isPunched = user.isPunched or false,
            character = user.character or "",
        }

        -- 头像地址拼接
        if user.avatar then
            if type(user.avatar) == "table" and user.avatar.fileServer and user.avatar.path then
                profile.avatar = user.avatar.fileServer .. "/static/" .. user.avatar.path
            elseif type(user.avatar) == "string" then
                profile.avatar = user.avatar
            end
        end

        return profile
    end

    return nil, data.message or "获取用户信息失败"
end

--- 打卡
function PicacgAuth:punchIn(http_client, headers)
    local token = self:getToken()
    if not token then
        return nil, "未登录"
    end

    local path = "users/punch-in"
    local url = headers:buildUrl(path)
    local req_headers = headers:build(path, "POST", token)

    local response, err = http_client:post(url, req_headers, "{}", 10)
    if not response then
        return nil, "网络请求失败: " .. tostring(err)
    end

    local data = http_client:parseJsonResponse(response)
    if data and data.code == 200 then
        return true
    end

    return nil, (data and data.message) or "打卡失败"
end

return PicacgAuth
