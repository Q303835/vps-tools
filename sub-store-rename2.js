function operator(proxies) {
  // 1. 安全检查
  if (!Array.isArray(proxies)) return [];
  
  const vpsMap = {};       // 核心：基于底层真实 IP/域名 进行同机多协议编号对齐
  const cityCounters = {};  // 核心：记录每个城市当前分配到第几台独立物理机器了

  // 厂家识别表
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

  // 地区精准识别顺序表
  const KEYS_PRIORITY = [
    // 亚洲城市
    "tokyo", "东京", "osaka", "大阪", "jposaka", "jpwest",
    "chuncheon", "春川", "seoul", "首尔",
    "hongkong", "香港", "taipei", "台北", "singapore", "新加坡",
    "mumbai", "孟买", "bangalore", "班加罗尔",
    "kualalumpur", "吉隆坡", "manila", "马尼拉", "bangkok", "曼谷",
    // 欧美澳城市
    "seattle", "西雅图", "sanjose", "圣何塞", "losangeles", "洛杉矶", "chicago", "芝加哥", "newyork", "纽约", "phoenix", "凤凰城", "ashburn", "阿什本", "oregon", "俄勒冈",
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

  // 【全新优化】对接主机命名规范：国家代码-城市缩写 (如 DE-frankfurt, HK 去重)
  const NAME_MAP = {
    // --- 亚洲 ---
    "tokyo": "JP-tyo", "东京": "JP-tyo", "osaka": "JP-osaka", "大阪": "JP-osaka", "jposaka": "JP-osaka", "jpwest": "JP-osaka", "japan": "JP", "日本": "JP", "jp": "JP",
    "hongkong": "HK", "香港": "HK", "hk": "HK",
    "taiwan": "TW", "台湾": "TW", "taipei": "TW", "台北": "TW", "tw": "TW",
    "singapore": "SG", "新加坡": "SG", "sg": "SG",
    "chuncheon": "KR-chuncheon", "春川": "KR-chuncheon", "seoul": "KR-seoul", "首尔": "KR-seoul", "korea": "KR", "韩国": "KR", "kr": "KR",
    "malaysia": "MY", "马来西亚": "MY", "kualalumpur": "MY", "吉隆坡": "MY", "my": "MY",
    "india": "IN", "印度": "IN", "mumbai": "IN-mumbai", "孟买": "IN-mumbai", "bangalore": "IN-blr", "班加罗尔": "IN-blr", "in": "IN",
    "philippines": "PH", "菲律宾": "PH", "manila": "PH-manila", "马尼拉": "PH-manila",
    "thailand": "TH", "泰国": "TH", "bangkok": "TH-bkk", "曼谷": "TH-bkk",
    "vietnam": "VN", "越南": "VN",
    
    // --- 欧洲 ---
    "london": "GB-lon", "伦敦": "GB-lon", "unitedkingdom": "GB", "英国": "GB", "uk": "GB", "gb": "GB",
    "frankfurt": "DE-frankfurt", "法兰克福": "DE-frankfurt", "germany": "DE", "德国": "DE", "de": "DE",
    "paris": "FR-paris", "巴黎": "FR-paris", "marseille": "FR-mrs", "马赛": "FR-mrs", "france": "FR", "法国": "FR", "fr": "FR",
    "amsterdam": "NL-ams", "阿姆斯特丹": "NL-ams", "netherlands": "NL", "荷兰": "NL", "nl": "NL",
    "stockholm": "SE-stockholm", "斯德哥尔摩": "SE-stockholm", "sweden": "SE", "瑞典": "SE", "se": "SE",
    "zurich": "CH-zurich", "苏黎世": "CH-zurich",
    
    // --- 美洲 ---
    "seattle": "US-seattle", "西雅图": "US-seattle", "sanjose": "US-sanjose", "圣何塞": "US-sanjose", "losangeles": "US-la", "洛杉矶": "US-la", 
    "chicago": "US-chicago", "芝加哥": "US-chicago", "newyork": "US-ny", "纽约": "US-ny", "phoenix": "US-phoenix", "凤凰城": "US-phoenix", 
    "ashburn": "US-virginia", "阿什本": "US-virginia", "oregon": "US-oregon", "俄勒冈": "US-oregon",
    "unitedstates": "US", "美国": "US", "us": "US",
    "canada": "CA", "加拿大": "CA", "toronto": "CA-toronto", "多伦多": "CA-toronto", "montreal": "CA-montreal", "蒙特利尔": "CA-montreal", "ca": "CA",
    "saopaulo": "BR-saopaulo", "圣保罗": "BR-saopaulo",
    
    // --- 澳洲及中东 ---
    "australia": "AU", "澳大利亚": "AU", "澳洲": "AU", "sydney": "AU-syd", "悉尼": "AU-syd", "melbourne": "AU-mel", "墨尔本": "AU-mel", "au": "AU",
    "dubai": "AE-dubai", "迪拜": "AE-dubai"
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
        // 同步修改这里的内置统计键名
        cityCounters["GCP-US-oregon"] = (cityCounters["GCP-US-oregon"] || 0) + 1;
        vpsMap[host] = cityCounters["GCP-US-oregon"];
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

      p.name = "GCP-US-oregon-" + resProto + v6Tag + "-" + currentVpsNum;
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

    // --- 4. 提取地区代码 (替换为英文/代码格式) ---
    let resLocation = "Unknown";
    for (var i = 0; i < KEYS_PRIORITY.length; i++) {
      var key = KEYS_PRIORITY[i];
      if (lowerName.indexOf(key) !== -1) {
        resLocation = NAME_MAP[key];
        break; 
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
    let host = serverAddr.split(':')[0]; 
    let vpsGroupKey = resProvider + "-" + resLocation; // 统计分组依据，如 "Oracle-KR-chuncheon"
    
    if (host && !vpsMap[host]) {
      cityCounters[vpsGroupKey] = (cityCounters[vpsGroupKey] || 0) + 1;
      vpsMap[host] = cityCounters[vpsGroupKey]; 
    }
    let currentVpsNum = vpsMap[host] || 1; 

    // --- 8. 组装最终纯文本名称（无任何旗帜与杂质干扰） ---
    // 最终输出格式：[厂商]-[国家]-[城市]-[协议]-[编号] (如 Oracle-DE-frankfurt-vl-1)
    p.name = resProvider + "-" + resLocation + "-" + resProtocol + v6Tag + "-" + currentVpsNum;

    return p;
  });
}