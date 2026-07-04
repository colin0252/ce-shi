<?xml version="1.0" encoding="UTF-8"?>
<swui:Application xmlns:swui="http://swui.com/schema"
                  title="游戏账号管理助手"
                  width="800" height="600"
                  theme="dark">

    <swui:Style>
        <style id="main-style">
            <background color="#1e1e2e"/>
            <font family="Microsoft YaHei" size="14"/>
        </style>
        
        <style id="card-style">
            <background color="#2d2d44" radius="10"/>
            <padding top="15" bottom="15" left="15" right="15"/>
            <margin top="10" bottom="10"/>
        </style>
        
        <style id="button-primary">
            <background color="#7289da"/>
            <foreground color="white"/>
            <padding top="8" bottom="8" left="20" right="20"/>
            <radius>5</radius>
            <cursor>hand</cursor>
        </style>
        
        <style id="button-danger">
            <background color="#f04747"/>
            <foreground color="white"/>
            <padding top="8" bottom="8" left="20" right="20"/>
            <radius>5</radius>
            <cursor>hand</cursor>
        </style>
        
        <style id="button-success">
            <background color="#43b581"/>
            <foreground color="white"/>
            <padding top="8" bottom="8" left="20" right="20"/>
            <radius>5</radius>
            <cursor>hand</cursor>
        </style>
    </swui:Style>

    <swui:Script>
        <![CDATA[
        // 全局状态管理
        var currentToken = null;
        var accounts = [];
        var qrCodeTimer = null;

        // 初始化
        function onLoad() {
            loadAccounts();
            generateQRCode();
        }

        // 生成QQ二维码
        function generateQRCode() {
            var qrContainer = getElement("qr-code-container");
            var appId = config.qq.app_id;
            var redirectUri = encodeURIComponent(config.qq.redirect_uri);
            var state = generateRandomState();
            
            var qrUrl = `https://graph.qq.com/oauth2.0/authorize?response_type=token&client_id=${appId}&redirect_uri=${redirectUri}&scope=${config.qq.scope}&state=${state}`;
            
            // 生成二维码图片
            qrContainer.innerHTML = `<img src="https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(qrUrl)}" alt="QQ二维码"/>`;
            
            // 开始轮询检查扫码状态
            startPolling(state);
        }

        // 刷新二维码
        function refreshQRCode() {
            if (qrCodeTimer) {
                clearInterval(qrCodeTimer);
            }
            generateQRCode();
            showMessage("二维码已刷新", "info");
        }

        // 轮询检查登录状态
        function startPolling(state) {
            var pollCount = 0;
            var maxPolls = 120; // 2分钟超时
            
            qrCodeTimer = setInterval(function() {
                pollCount++;
                if (pollCount > maxPolls) {
                    clearInterval(qrCodeTimer);
                    showMessage("二维码已过期，请刷新", "warning");
                    return;
                }
                
                // 检查扫码状态
                checkLoginStatus(state);
            }, 1000);
        }

        // 检查登录状态
        function checkLoginStatus(state) {
            fetch(`/api/check-login?state=${state}`)
                .then(response => response.json())
                .then(data => {
                    if (data.success && data.token) {
                        clearInterval(qrCodeTimer);
                        currentToken = data.token;
                        updateTokenDisplay(data.token);
                        showMessage("扫码登录成功！", "success");
                    }
                })
                .catch(error => {
                    console.error("检查登录状态失败:", error);
                });
        }

        // 更新Token显示
        function updateTokenDisplay(token) {
            var tokenInput = getElement("token-input");
            tokenInput.value = token;
            
            var tokenStatus = getElement("token-status");
            tokenStatus.text = "● 已登录";
            tokenStatus.style.color = "#43b581";
        }

        // 手动输入Token
        function manualTokenInput() {
            var token = getElement("token-input").value.trim();
            if (!token) {
                showMessage("请输入Token", "warning");
                return;
            }
            
            currentToken = token;
            updateTokenDisplay(token);
            showMessage("Token已设置", "success");
        }

        // 一键复制Token
        function copyToken() {
            if (!currentToken) {
                showMessage("请先获取Token", "warning");
                return;
            }
            
            navigator.clipboard.writeText(currentToken).then(function() {
                showMessage("Token已复制到剪贴板", "success");
            }).catch(function() {
                // 降级方案
                var tokenInput = getElement("token-input");
                tokenInput.select();
                document.execCommand("copy");
                showMessage("Token已复制到剪贴板", "success");
            });
        }

        // 游戏登录
        function loginGame(gameCode) {
            if (!currentToken) {
                showMessage("请先获取Token", "warning");
                return;
            }
            
            var gameName = config.games[gameCode].name;
            showMessage(`正在登录${gameName}...`, "info");
            
            var gameConfig = config.games[gameCode];
            fetch(gameConfig.api_base + gameConfig.login_endpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer ' + currentToken
                },
                body: JSON.stringify({
                    token: currentToken,
                    game: gameCode
                })
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    showMessage(`${gameName}登录成功！`, "success");
                    saveAccount(gameName, gameCode, data.account);
                } else {
                    showMessage(`${gameName}登录失败：${data.message}`, "error");
                }
            })
            .catch(error => {
                showMessage(`${gameName}登录失败：网络错误`, "error");
            });
        }

        // 保存账号
        function saveAccount(gameName, gameCode, accountData) {
            var account = {
                id: Date.now(),
                gameName: gameName,
                gameCode: gameCode,
                username: accountData.username || accountData.uid,
                uid: accountData.uid,
                loginTime: new Date().toLocaleString(),
                token: currentToken
            };
            
            // 检查是否已存在
            var existingIndex = accounts.findIndex(a => a.gameCode === gameCode && a.uid === account.uid);
            if (existingIndex >= 0) {
                accounts[existingIndex] = account;
            } else {
                accounts.push(account);
            }
            
            // 保存到本地存储
            localStorage.setItem('game_accounts', JSON.stringify(accounts));
            
            // 同时保存到数据库
            saveAccountToDB(account);
            
            refreshAccountList();
        }

        // 保存到数据库
        function saveAccountToDB(account) {
            fetch('/api/accounts/save', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(account)
            })
            .then(response => response.json())
            .then(data => {
                console.log("账号已保存到数据库");
            })
            .catch(error => {
                console.error("保存到数据库失败:", error);
            });
        }

        // 加载账号列表
        function loadAccounts() {
            var savedAccounts = localStorage.getItem('game_accounts');
            if (savedAccounts) {
                accounts = JSON.parse(savedAccounts);
            }
            
            // 也从数据库加载
            loadAccountsFromDB();
            
            refreshAccountList();
        }

        // 从数据库加载
        function loadAccountsFromDB() {
            fetch('/api/accounts/list')
                .then(response => response.json())
                .then(data => {
                    if (data.accounts && data.accounts.length > 0) {
                        // 合并账号数据
                        data.accounts.forEach(dbAccount => {
                            var exists = accounts.find(a => a.id === dbAccount.id);
                            if (!exists) {
                                accounts.push(dbAccount);
                            }
                        });
                        localStorage.setItem('game_accounts', JSON.stringify(accounts));
                        refreshAccountList();
                    }
                })
                .catch(error => {
                    console.error("从数据库加载失败:", error);
                });
        }

        // 刷新账号列表显示
        function refreshAccountList() {
            var accountList = getElement("account-list");
            accountList.innerHTML = "";
            
            if (accounts.length === 0) {
                accountList.innerHTML = "<div style='text-align:center;color:#888;padding:20px;'>暂无账号，请先登录游戏</div>";
                return;
            }
            
            accounts.forEach(function(account) {
                var card = document.createElement("div");
                card.className = "account-card";
                card.innerHTML = `
                    <div class="account-info">
                        <div class="account-game">${account.gameName}</div>
                        <div class="account-uid">UID: ${account.uid}</div>
                        <div class="account-time">登录时间: ${account.loginTime}</div>
                    </div>
                    <div class="account-actions">
                        <button onclick="copyAccountUID('${account.uid}')" class="btn-copy" title="复制UID">
                            📋 复制
                        </button>
                        <button onclick="deleteAccount('${account.id}')" class="btn-delete" title="删除账号">
                            🗑️ 删除
                        </button>
                    </div>
                `;
                accountList.appendChild(card);
            });
        }

        // 复制账号UID
        function copyAccountUID(uid) {
            navigator.clipboard.writeText(uid).then(function() {
                showMessage("UID已复制到剪贴板", "success");
            }).catch(function() {
                showMessage("复制失败", "error");
            });
        }

        // 删除账号
        function deleteAccount(accountId) {
            if (confirm("确定要删除这个账号吗？")) {
                // 从本地删除
                accounts = accounts.filter(function(a) {
                    return a.id != accountId;
                });
                localStorage.setItem('game_accounts', JSON.stringify(accounts));
                
                // 从数据库删除
                fetch(`/api/accounts/delete/${accountId}`, {
                    method: 'DELETE'
                }).catch(error => {
                    console.error("从数据库删除失败:", error);
                });
                
                refreshAccountList();
                showMessage("账号已删除", "info");
            }
        }

        // 清空所有账号
        function clearAllAccounts() {
            if (accounts.length === 0) {
                showMessage("没有可删除的账号", "info");
                return;
            }
            
            if (confirm("确定要删除所有账号吗？此操作不可恢复！")) {
                accounts = [];
                localStorage.removeItem('game_accounts');
                
                fetch('/api/accounts/clear', {
                    method: 'DELETE'
                }).catch(error => {
                    console.error("清空数据库失败:", error);
                });
                
                refreshAccountList();
                showMessage("所有账号已清空", "info");
            }
        }

        // 生成随机state
        function generateRandomState() {
            return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
        }

        // 显示消息
        function showMessage(message, type) {
            var msgContainer = getElement("message-container");
            var msgDiv = document.createElement("div");
            msgDiv.className = "message message-" + type;
            msgDiv.textContent = message;
            
            msgContainer.appendChild(msgDiv);
            
            // 3秒后自动消失
            setTimeout(function() {
                msgDiv.remove();
            }, 3000);
        }

        function getElement(id) {
            return document.getElementById(id);
        }
        ]]>
    </swui:Script>

    <swui:Layout type="vertical" padding="20">
        
        <!-- 消息提示容器 -->
        <swui:Container id="message-container" height="auto" style="position:fixed;top:20px;right:20px;z-index:1000;"/>
        
        <!-- 标题 -->
        <swui:Label text="游戏账号管理助手" font-size="24" font-weight="bold" 
                     foreground="#7289da" alignment="center" margin-bottom="20"/>
        
        <!-- Token区域 -->
        <swui:Card style="card-style">
            <swui:Label text="🔑 Token管理" font-size="18" font-weight="bold" margin-bottom="10"/>
            
            <swui:Layout type="horizontal" margin-bottom="10">
                <swui:TextBox id="token-input" width="400" placeholder="Token将自动填充或手动输入..." 
                               password="true" height="35"/>
                <swui:Button text="📋 复制" onclick="copyToken()" style="button-primary" margin-left="10"/>
                <swui:Button text="✔️ 确认" onclick="manualTokenInput()" style="button-success" margin-left="5"/>
                <swui:Label id="token-status" text="● 未登录" foreground="#f04747" margin-left="10"/>
            </swui:Layout>
        </swui:Card>
        
        <!-- QQ二维码区域 -->
        <swui:Card style="card-style">
            <swui:Label text="📱 QQ扫码登录" font-size="18" font-weight="bold" margin-bottom="10"/>
            
            <swui:Layout type="horizontal" alignment="center">
                <swui:Layout type="vertical" alignment="center">
                    <swui:Container id="qr-code-container" width="200" height="200" 
                                     style="border:2px solid #7289da;border-radius:10px;padding:5px;"/>
                    <swui:Button text="🔄 刷新二维码" onclick="refreshQRCode()" 
                                  style="button-primary" margin-top="10"/>
                </swui:Layout>
                
                <swui:Layout type="vertical" margin-left="30">
                    <swui:Label text="使用说明：" font-size="16" font-weight="bold" margin-bottom="10"/>
                    <swui:Label text="1. 打开手机QQ扫描左侧二维码" font-size="14"/>
                    <swui:Label text="2. 在手机上确认授权登录" font-size="14"/>
                    <swui:Label text="3. 等待自动获取Token" font-size="14"/>
                    <swui:Label text="4. Token将自动填充到上方输入框" font-size="14"/>
                </swui:Layout>
            </swui:Layout>
        </swui:Card>
        
        <!-- 游戏登录区域 -->
        <swui:Card style="card-style">
            <swui:Label text="🎮 游戏登录" font-size="18" font-weight="bold" margin-bottom="10"/>
            
            <swui:Layout type="horizontal" alignment="space-around">
                <swui:Layout type="vertical" alignment="center">
                    <swui:Image src="./icons/delta_force.png" width="80" height="80" margin-bottom="5"/>
                    <swui:Label text="三角洲行动" font-size="14" margin-bottom="5"/>
                    <swui:Button text="🚀 登录" onclick="loginGame('delta_force')" 
                                  style="button-success" width="120"/>
                </swui:Layout>
                
                <swui:Layout type="vertical" alignment="center">
                    <swui:Image src="./icons/dark_zone.png" width="80" height="80" margin-bottom="5"/>
                    <swui:Label text="暗区突围" font-size="14" margin-bottom="5"/>
                    <swui:Button text="🚀 登录" onclick="loginGame('dark_zone')" 
                                  style="button-success" width="120"/>
                </swui:Layout>
                
                <swui:Layout type="vertical" alignment="center">
                    <swui:Image src="./icons/peace_elite.png" width="80" height="80" margin-bottom="5"/>
                    <swui:Label text="和平精英" font-size="14" margin-bottom="5"/>
                    <swui:Button text="🚀 登录" onclick="loginGame('peace_elite')" 
                                  style="button-success" width="120"/>
                </swui:Layout>
            </swui:Layout>
        </swui:Card>
        
        <!-- 账号列表区域 -->
        <swui:Card style="card-style">
            <swui:Layout type="horizontal" alignment="space-between" margin-bottom="10">
                <swui:Label text="📋 已保存的账号" font-size="18" font-weight="bold"/>
                <swui:Button text="🗑️ 清空所有" onclick="clearAllAccounts()" 
                              style="button-danger" width="100"/>
            </swui:Layout>
            
            <swui:ScrollView height="200">
                <swui:Container id="account-list" width="100%">
                    <!-- 动态生成的账号卡片 -->
                </swui:Container>
            </swui:ScrollView>
        </swui:Card>
        
    </swui:Layout>

    <!-- 底部状态栏 -->
    <swui:StatusBar>
        <swui:Label text="版本 1.0.0 | 游戏账号管理助手" font-size="12" foreground="#888"/>
    </swui:StatusBar>

</swui:Application>