function operator(proxies) {
  // 1. 安全检查
  if (!Array.isArray(proxies)) return [];
  
  const vpsMap = {};       // 核心：基于底层真实 IP/域名 进行同机多协议编号对齐
  const cityCounters = {};  // 核心：记录每个城市当前分配到第几台独立物理机器了

  // 厂家识别表（涵盖御三家、主流VPS及国内出海大厂）
  const PROVIDER_MAP = {
    "gcp": "GCP", "google": "GCP",
    "aws": "AWS", "amazon": "AWS",
    "azure": "Azure", "微软": "Azure",
    "oracle": "Oracle", "甲骨文": "Oracle",
    "do": "DO", "digitalocean": "DO",
    "vultr": "Vultr",
    "linode": "Linode", "akamai": "Linode",
    "hetzner": "Hetzner",
    "ovh": "OVH",
    "bwh": "搬瓦工", "bandwagon": "搬瓦工",
    "dmit": "DMIT",
    "rn": "RackNerd", "racknerd": "RackNerd",
    "cc": "CloudCone", "cloudcone": "CloudCone",
    "kurun": "Kurun",
    "aliyun": "阿里云", "alibaba": "阿里云",
    "tencent": "腾讯云",
    "cf": "CF", "cloudflare": "CF", "workers": "CF", "pages": "CF"
  };

  // 地区精准识别顺序表（手动调整顺序，长词/高精准词靠前，缩写靠后防止误伤）
  const KEYS_PRIORITY = [
    // 亚洲城市
    "tokyo", "东京", "osaka", "大阪", "jposaka", "jpwest",
    "chuncheon", "春川", "seoul", "首尔",
    "hongkong", "香港", "taipei", "台北", "singapore", "新加坡",
    "mumbai", "孟买", "bangalore", "班加罗尔",
    "kualalumpur", "吉隆坡", "manila", "马尼拉", "bangkok", "曼谷",
    // 欧美澳城市
    "seattle", "西雅图", "sanjose", "圣何塞", "losangeles", "洛杉矶", "chicago", "芝加哥", "newyork", "纽约", "phoenix", "凤凰城", "ashburn", "阿什本",
    "london", "伦敦", "frankfurt", "法兰克福", "paris", "巴黎", "marseille", "马赛",
    "amsterdam", "阿姆斯特丹", "stockholm", "斯德哥尔摩", "zurich", "苏黎世",
    "sydney", "悉尼", "melbourne", "墨尔本",
    "toronto", "多伦多", "montreal", "蒙特利尔", "saopaulo", "圣保罗", "dubai", "迪拜",
    
    // 国家/地区长词
    "taiwan", "台湾", "unitedkingdom", "英国", "unitedstates", "美国",
    "japan", "日本", "korea", "韩国", "malaysia", "马来西亚", 
    "sweden", "瑞典", "germany", "德国", "france", "法国", "netherlands", "荷兰",
    "australia", "澳大利亚", "澳洲", "canada", "加拿大", 
    "india", "印度", "philippines", "菲律宾", "thailand", "泰国", "vietnam", "越南",
    
    // 两个字母的缩写必须放在最后！
    "jp", "us", "de", "se", "in", "kr", "uk", "gb", "hk", "sg", "my", "tw", "fr", "nl", "au", "ca"
  ];

  // 统一汉化名称表
  const NAME_MAP = {
    // --- 亚洲 ---
    "tokyo": "东京", "东京": "东京", "osaka": "大阪", "大阪": "大阪", "jposaka": "大阪", "jpwest": "大阪", "japan": "日本", "日本": "日本", "jp": "日本",
    "hongkong": "香港", "香港": "香港", "hk": "香港",
    "taiwan": "台湾", "台湾": "台湾", "taipei": "台湾", "台北": "台湾", "tw": "台湾",
    "singapore": "新加坡", "新加坡": "新加坡", "sg": "新加坡",
    "chuncheon": "春川", "春川": "春川", "seoul": "首尔", "首尔": "首尔", "korea": "春川", "韩国": "春川", "kr": "春川", // 韩国特判统一为春川
    "malaysia": "马来西亚", "马来西亚": "马来西亚", "kualalumpur": "马来西亚", "吉隆坡": "马来西亚", "my": "马来西亚",
    "india": "印度", "印度": "印度", "mumbai": "孟买", "孟买": "孟买", "bangalore": "班加罗尔", "班加罗尔": "班加罗尔", "in": "印度",
    "philippines": "菲律宾", "菲律宾": "菲律宾", "manila": "菲律宾", "马尼拉": "菲律宾",
    "thailand": "泰国", "泰国": "泰国", "bangkok": "泰国", "曼谷": "泰国",
    "vietnam": "越南", "越南": "越南",
    
    // --- 欧洲 ---
    "london": "英国", "伦敦": "英国", "unitedkingdom": "英国", "英国": "英国", "uk": "英国", "gb": "英国",
    "frankfurt": "法兰克福", "法兰克福": "法兰克福", "germany": "德国", "德国": "德国", "de": "德国",
    "paris": "法国", "巴黎": "法国", "marseille": "法国", "马赛": "法国", "france": "法国", "法国": "法国", "fr": "法国",
    "amsterdam": "荷兰", "阿姆斯特丹": "荷兰", "netherlands": "荷兰", "荷兰": "荷兰", "nl": "荷兰",
    "stockholm": "斯德哥尔摩", "斯德哥尔摩": "斯德哥尔摩", "sweden": "瑞典", "瑞典": "瑞典", "se": "瑞典",
    "zurich": "瑞士", "苏黎世": "瑞士",
    
    // --- 美洲 ---
    "seattle": "西雅图", "西雅图": "西雅图", "sanjose": "圣何塞", "圣何塞": "圣何塞", "losangeles": "洛杉矶", "洛杉矶": "洛杉矶", 
    "chicago": "芝加哥", "芝加哥": "芝加哥", "newyork": "纽约", "纽约": "纽约", "phoenix": "凤凰城", "凤凰城": "凤凰城", "ashburn": "阿什本", "阿什本": "阿什本",
    "unitedstates": "美国", "美国": "美国", "us": "美国",
    "canada": "加拿大", "加拿大": "加拿大", "toronto": "加拿大", "多伦多": "加拿大", "montreal": "加拿大", "蒙特利尔": "加拿大", "ca": "加拿大",
    "saopaulo": "巴西", "圣保罗": "巴西",
    
    // --- 澳洲及中东 ---
    "australia": "澳大利亚", "澳大利亚": "澳大利亚", "澳洲": "澳大利亚", "sydney": "悉尼", "悉尼": "悉尼", "melbourne": "墨尔本", "墨尔本": "墨尔本", "au": "澳大利亚",
    "dubai": "迪拜", "迪拜": "迪拜"
  };

  // 核心协议类型提取表
  const PROTOCOLS = ["vmess", "vless", "vm", "vl", "hy2", "hysteria", "tuic", "tu5", "anytls", "shadowsocks", "ss"];

  return proxies.map(p => {
    p.flag = false; // 1. 全局禁用 Sub-Store 内置国旗，彻底移除任何海盗旗 🏴‍☠️
    if (!p) return p;

    // 提取并清理底层的服务器网络地址和原始名称
    let serverAddr = p.server ? p.server.toLowerCase() : "";
    let cleanName = p.name ? p.name.replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]|\u2705|\u270A|\u2122/g, '').trim() : "";
    let lowerName = cleanName.toLowerCase();
    
    // --- 2. 【最高优先级】免费机底层地址硬拦截补丁 ---
    if (
      lowerName.indexOf("us-free") !== -1 || 
      lowerName.indexOf("usfree") !== -1 ||
      serverAddr.indexOf("gcp.123690.app") !== -1 ||
      serverAddr.indexOf("35.212.") === 0 ||
      serverAddr.indexOf("34.3.") === 0
    ) {
      let host = serverAddr.split(':')[0];
      if (host && !vpsMap[host]) {
        cityCounters["gcp-俄勒冈"] = (cityCounters["gcp-俄勒冈"] || 0) + 1;
        vpsMap[host] = cityCounters["gcp-俄勒冈"];
      }
      let currentVpsNum = vpsMap[host] || 1;

      let resProto = "proxy";
      for (let proto of PROTOCOLS) {
        if (lowerName.indexOf(proto) !== -1 || (p.type && p.type.toLowerCase().indexOf(proto) !== -1)) {
          resProto = proto.replace("shadowsocks", "ss").replace("hysteria", "hy").replace("vless", "vl").replace("vmess", "vm").replace("tu5", "tuic");
          break;
        }
      }
      let v6Tag = (serverAddr.indexOf(":") !== -1) ? "-v6" : "";

      p.name = "GCP-俄勒冈-" + resProto + v6Tag + "-" + currentVpsNum;
      return p;
    }

    // --- 3. 提取厂商 ---
    let resProvider = "Other";
    for (let key in PROVIDER_MAP) {
      if (lowerName.indexOf(key) !== -1) {
        resProvider = PROVIDER_MAP[key];
        break;
      }
    }

    // --- 4. 提取中文城市/地区 ---
    let resLocation = "未知";
    for (var i = 0; i < KEYS_PRIORITY.length; i++) {
      var key = KEYS_PRIORITY[i];
      if (lowerName.indexOf(key) !== -1) {
        resLocation = NAME_MAP[key];
        break; // 匹配到高精准词后立刻拦截跳出，保证城市级精度
      }
    }

    // --- 5. 提取协议简称 ---
    let resProtocol = "proxy";
    for (let proto of PROTOCOLS) {
      if (lowerName.indexOf(proto) !== -1 || (p.type && p.type.toLowerCase().indexOf(proto) !== -1)) {
        resProtocol = proto.replace("shadowsocks", "ss").replace("hysteria", "hy").replace("vless", "vl").replace("vmess", "vm").replace("tu5", "tuic");
        break;
      }
    }

    // --- 6. IPv6 动态检测 ---
    let v6Tag = (serverAddr.indexOf(":") !== -1) ? "-v6" : "";

    // --- 7. 【核心高阶设计】按真实物理主机 IP 进行同机多协议编号精准对齐 ---
    let host = serverAddr.split(':')[0]; // 剥离端口，锁定物理 IP 或域名
    let vpsGroupKey = resProvider + "-" + resLocation; // 统计分组依据：如 "Oracle-春川"
    
    if (host && !vpsMap[host]) {
      // 如果这个 IP 之前没记录过，说明检测到该区域的一台新物理机，该城市机器计数加 1
      cityCounters[vpsGroupKey] = (cityCounters[vpsGroupKey] || 0) + 1;
      vpsMap[host] = cityCounters[vpsGroupKey]; // 为这台物理 VPS 永久绑定它的专属机器编号
    }
    let currentVpsNum = vpsMap[host] || 1; // 提取这台主机的真实数字代号

    // --- 8. 组装最终纯文本名称（无任何旗帜与杂质干扰） ---
    p.name = resProvider + "-" + resLocation + "-" + resProtocol + v6Tag + "-" + currentVpsNum;

    return p;
  });
}
