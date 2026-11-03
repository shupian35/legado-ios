/// The default data that upstream ships in `app/src/main/assets/defaultData/`.
///
/// Upstream `io.legado.app.help.DefaultData` reads the very same JSON files.
/// The content is embedded as raw string literals so that the core stays
/// free of a resource bundle and the JSON escapes survive unchanged.
enum DefaultDataJSON {
    /// `assets/defaultData/txtTocRule.json`.
    static let txtTocRule = #"""
    [
      {
        "id": -1,
        "enable": true,
        "name": "目录(去空白)",
        "rule": "(?<=[　\\s])(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和]))).{0,30}$",
        "example": "第一章 假装第一章前面有空白但我不要",
        "serialNumber": 0
      },
      {
        "id": -2,
        "enable": true,
        "name": "目录",
        "rule": "^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$",
        "example": "第一章 标准的粤语就是这样",
        "serialNumber": 1
      },
      {
        "id": -3,
        "enable": false,
        "name": "目录(匹配简介)",
        "rule": "(?<=[　\\s])(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|篇(?!张))).{0,30}$",
        "example": "简介 老夫诸葛村夫",
        "serialNumber": 2
      },
      {
        "id": -4,
        "enable": false,
        "name": "目录(古典、轻小说备用)",
        "rule": "^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|话|篇(?!张))).{0,30}$",
        "example": "第一章 比上面只多了回和话",
        "serialNumber": 3
      },
      {
        "id": -5,
        "enable": false,
        "name": "数字(纯数字标题)",
        "rule": "(?<=[　\\s])\\d+\\.?[ 　\\t]{0,4}$",
        "example": "12",
        "serialNumber": 4
      },
      {
        "id": -6,
        "enable": false,
        "name": "大写数字(纯数字标题)",
        "rule": "(?<=[　\\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,12}[ 　\\t]{0,4}$",
        "example": "一百七十",
        "serialNumber": 5
      },
      {
        "id": -7,
        "enable": false,
        "name": "数字混合(纯数字标题)",
        "rule": "(?<=[　\\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\\d]{1,12}[ 　\\t]{0,4}$",
        "example": "12\n一百七十",
        "serialNumber": 6
      },
      {
        "id": -8,
        "enable": true,
        "name": "数字 分隔符 标题名称",
        "rule": "^[ 　\\t]{0,4}\\d{1,5}[:：,.， 、_—\\-].{1,30}$",
        "example": "1、这个就是标题",
        "serialNumber": 7
      },
      {
        "id": -9,
        "enable": true,
        "name": "大写数字 分隔符 标题名称",
        "rule": "^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?)[ 、_—\\-].{1,30}$",
        "example": "一、只有前面的数字有差别\n二十四章 我瞎编的标题",
        "serialNumber": 8
      },
      {
        "id": -10,
        "enable": false,
        "name": "数字混合 分隔符 标题名称",
        "rule": "^[ 　\\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?[ 、_—\\-]|\\d{1,5}章?[:：,.， 、_—\\-]).{0,30}$",
        "example": "1、人参公鸡\n二百二十章 boy next door",
        "serialNumber": 9
      },
      {
        "id": -11,
        "enable": true,
        "name": "正文 标题/序号",
        "rule": "^[ 　\\t]{0,4}正文[ 　]{1,4}.{0,20}$",
        "example": "正文 我奶常山赵子龙",
        "serialNumber": 10
      },
      {
        "id": -12,
        "enable": true,
        "name": "Chapter/Section/Part/Episode 序号 标题",
        "rule": "^[ 　\\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO][.、]|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\\s{0,4}\\d{1,4}.{0,30}$",
        "example": "Chapter 1 MyGrandmaIsNB",
        "serialNumber": 11
      },
      {
        "id": -13,
        "enable": false,
        "name": "Chapter(去简介)",
        "rule": "^[ 　\\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][Oo]\\.|[Ee]pisode)\\s{0,4}\\d{1,4}.{0,30}$",
        "example": "Chapter 1 MyGrandmaIsNB",
        "serialNumber": 12
      },
      {
        "id": -14,
        "enable": true,
        "name": "特殊符号 序号 标题",
        "rule": "(?<=[\\s　])[【〔〖「『〈［\\[](?:第|[Cc]hapter)[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,20}$",
        "example": "【第一章 后面的符号可以没有",
        "serialNumber": 13
      },
      {
        "id": -15,
        "enable": false,
        "name": "特殊符号 标题(成对)",
        "rule": "(?<=[\\s　]{0,4})(?:[\\[〈「『〖〔《（【\\(].{1,30}[\\)】）》〕〗』」〉\\]]?|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$",
        "example": "『加个直角引号更专业』\n(11)我奶常山赵子聋",
        "serialNumber": 14
      },
      {
        "id": -16,
        "enable": true,
        "name": "特殊符号 标题(单个)",
        "rule": "(?<=[\\s　]{0,4})(?:[☆★✦✧].{1,30}|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$",
        "example": "☆、晋江作者最喜欢的格式",
        "serialNumber": 15
      },
      {
        "id": -17,
        "enable": true,
        "name": "章/卷 序号 标题",
        "rule": "^[ \\t　]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 　]{0,4}.{0,30}$",
        "example": "卷五 开源盛世",
        "serialNumber": 16
      },
      {
        "id": -18,
        "enable": false,
        "name": "顶格标题",
        "rule": "^\\S.{1,20}$",
        "example": "20字以内顶格写的都是标题",
        "serialNumber": 17
      },
      {
        "id": -19,
        "enable": false,
        "name": "双标题(前向)",
        "rule": "(?m)(?<=[ \\t　]{0,4})第[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$(?=[\\s　]{0,8}第[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章)",
        "example": "第一章 真正的标题\n第一章 这个不要",
        "serialNumber": 18
      },
      {
        "id": -20,
        "enable": false,
        "name": "双标题(后向)",
        "rule": "(?m)(?<=[ \\t　]{0,4}第[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$[\\s　]{0,8})第[\\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$",
        "example": "第一章 这个标题不要\n第一章真正的标题",
        "serialNumber": 19
      },
      {
        "id": -21,
        "enable": true,
        "name": "书名 括号 序号",
        "rule": "^[一-龥]{1,20}[ 　\\t]{0,4}[(（][\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ 　\\t]{0,4}$",
        "example": "标题后面数字有括号(12)",
        "serialNumber": 20
      },
      {
        "id": -22,
        "enable": true,
        "name": "书名 序号",
        "rule": "^[一-龥]{1,20}[ 　\\t]{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[ 　\\t]{0,4}$",
        "example": "标题后面数字没有括号124",
        "serialNumber": 21
      },
      {
        "id": -23,
        "enable": false,
        "name": "特定字符 标题 特定符号",
        "rule": "(?<=\\={3,6}).{1,40}?(?=\\=)",
        "example": "===起这种标题干什么===",
        "serialNumber": 22
      },
      {
        "id": -24,
        "enable": true,
        "name": "字数分割 分节阅读",
        "rule": "(?<=[ 　\\t]{0,4})(?:.{0,15}分[页节章段]阅读[-_ ]|第\\s{0,4}[\\d零一二两三四五六七八九十百千万]{1,6}\\s{0,4}[页节]).{0,30}$",
        "example": "分节|分页|分段阅读\n第一页",
        "serialNumber": 23
      },
      {
        "id": -25,
        "enable": false,
        "name": "通用规则",
        "rule": "(?im)^.{0,6}(?:[引楔]子|正文(?!完|结)|[引序前]言|[序终]章|扉页|[上中下][部篇卷]|卷首语|后记|尾声|番外|={2,4}|第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}(?:章|节(?!课)|卷|页[、 　]|集(?![合和])|部(?![分是门落])|篇(?!张))).{0,40}$|^.{0,6}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟a-z]{1,8}[、. 　].{0,20}$",
        "example": "激进规则,适配更多非常用格式",
        "serialNumber": 24
      },
      {
        "id": -100,
        "enable": false,
        "name": "默认分章规则",
        "rule": "",
        "example": "兜底规则，请勿改动此内容",
        "serialNumber": 99
      }
    ]
    """#

    /// `assets/defaultData/rssSources.json`.
    static let rssSources = #"""
    [
      {
        "customOrder": 2,
        "enableJs": true,
        "enabled": true,
        "singleUrl": true,
        "sourceGroup": "legado",
        "sourceIcon": "https://cdn.jsdelivr.net/gh/gedoor/legado@master/app/src/main/res/mipmap-hdpi/ic_launcher.png",
        "sourceName": "使用说明",
        "sourceUrl": "https://www.yuque.com/legado"
      },
      {
        "customOrder": 3,
        "enableJs": true,
        "enabled": true,
        "singleUrl": true,
        "sourceGroup": "legado",
        "sourceIcon": "http://mmbiz.qpic.cn/mmbiz_png/hpfMV8hEuL2eS6vnCxvTzoOiaCAibV6exBzJWq9xMic9xDg3YXAick87tsfafic0icRwkQ5ibV0bJ84JtSuxhPuEDVquA/0?wx_fmt=png",
        "sourceName": "小说拾遗",
        "sourceUrl": "snssdk1128://user/profile/562564899806367"
      },
      {
        "customOrder": 4,
        "enableJs": true,
        "enabled": true,
        "singleUrl": true,
        "sourceGroup": "legado",
        "sourceIcon": "https://cdn.jsdelivr.net/gh/mgz0227/meowcloud/icon.png",
        "sourceName": "Meow云",
        "sourceUrl": "https://pan.miaogongzi.net"
      },
      {
        "customOrder": 5,
        "enableJs": true,
        "enabled": true,
        "singleUrl": true,
        "sourceGroup": "legado",
        "sourceIcon": "https://cdn.jsdelivr.net/gh/gedoor/legado@master/app/src/main/res/mipmap-hdpi/ic_launcher.png",
        "sourceName": "烏雲净化",
        "sourceUrl": "https://www.lanzoux.com/b0bw8jwoh"
      }
    ]
    """#

    /// `assets/defaultData/dictRules.json`.
    static let dictRules = #"""
    [
      {
        "name": "百度汉语",
        "urlRule": "https://dict.baidu.com/s?wd={{key}}",
        "showRule": "@js:var jsoup = org.jsoup.Jsoup.parse(result)\njsoup.select(\"script,#search-bar,#right-panel,#copyright\").remove()\njsoup.select(\"#poem-list-items\").html()",
        "enabled": true,
        "sortNumber": 2
      },
      {
        "name": "海词英文",
        "urlRule": "https://apii.dict.cn/mini.php?q={{key}}",
        "showRule": "tag.body@all",
        "enabled": true,
        "sortNumber": 1
      },
      {
      "name": "海词中文",
      "urlRule": "https://hanyu.dict.cn/{{key}}",
      "showRule": "@js:var jsoup = org.jsoup.Jsoup.parse(result)\njsoup.select(\"script,#header,#footer,#page-share,.mslide,.title,#dictHcBtn,#dictHcBtnTop,#dictHc,#dictHc,#dictHcSettingArea,#dictHcClosetip\").remove()\njsoup.select(\"#cy\").html()",
      "enabled": true,
      "sortNumber": 0
      }
    ]
    """#

    /// `assets/defaultData/httpTTS.json`.
    static let httpTTS = #"""
    [
      {
        "id": -100,
        "name": "1.百度",
        "url": "http://tts.baidu.com/text2audio,{\n    \"method\": \"POST\",\n    \"body\": \"tex={{java.encodeURI(java.encodeURI(speakText))}}&spd={{(speakSpeed + 5) / 10 + 4}}&per=3&cuid=baidu_speech_demo&idx=1&cod=2&lan=zh&ctp=1&pdt=160&vol=5&aue=6&pit=5&_res_tag_=audio\"\n}",
        "contentType": "audio/wav"
      },
      {
        "id": -29,
        "name": "2.阿里云语音",
        "url": "https://nls-gateway.cn-shanghai.aliyuncs.com/stream/v1/tts,{\"method\": \"POST\",\"body\": {\"appkey\":\"{{source.getLoginInfoMap().get('AppKey')}}\",\"text\":\"{{speakText}}\",\"format\":\"mp3\",\"volume\":100,\"speech_rate\":{{String((speakSpeed) * 20 - 400)}} }}",
        "contentType": "audio/mpeg",
        "loginUrl": "function login(){var loginInfo = source.getLoginInfoMap();\nvar accessKeyId = loginInfo.get('AccessKeyId');\nvar accessKeySecret = loginInfo.get('AccessKeySecret');\nvar timestamp = java.timeFormatUTC(new Date().getTime(), \"yyyy-MM-dd'T'HH:mm:ss'Z'\", 0);\nvar aly = new JavaImporter(Packages.javax.crypto.Mac, Packages.javax.crypto.spec.SecretKeySpec, Packages.javax.xml.bind.DatatypeConverter, Packages.java.net.URLEncoder, Packages.java.lang.String, Packages.android.util.Base64);\nwith (aly) {\n    function percentEncode(value) {\n        return URLEncoder.encode(value, \"UTF-8\").replace(\"+\", \"%20\")\n            .replace(\"*\", \"%2A\").replace(\"%7E\", \"~\")\n    }\n\n    function sign(stringToSign, accessKeySecret) {\n        var mac = Mac.getInstance('HmacSHA1');\n        mac.init(new SecretKeySpec(String(accessKeySecret + '&').getBytes(\"UTF-8\"), \"HmacSHA1\"));\n        var signData = mac.doFinal(String(stringToSign).getBytes(\"UTF-8\"));\n        var signBase64 = Base64.encodeToString(signData, Base64.NO_WRAP);\n        var signUrlEncode = percentEncode(signBase64);\n        return signUrlEncode;\n    }\n}\nvar query = 'AccessKeyId=' + accessKeyId + '&Action=CreateToken&Format=JSON&RegionId=cn-shanghai&SignatureMethod=HMAC-SHA1&SignatureNonce=' + java.randomUUID() + '&SignatureVersion=1.0&Timestamp=' + percentEncode(timestamp) + '&Version=2019-02-28';\nvar signStr = sign('GET&' + percentEncode('/') + '&' + percentEncode(query), accessKeySecret);\nvar queryStringWithSign = \"Signature=\" + signStr + \"&\" + query;\nvar body = java.ajax('http://nls-meta.cn-shanghai.aliyuncs.com/?' + queryStringWithSign)\nvar res = JSON.parse(body)\nif (res.Message) {\n    throw new Error(res.Message)\n}\nvar header = { \"X-NLS-Token\": res.Token.Id };\nsource.putLoginHeader(JSON.stringify(header))}",
        "loginUi": [
          {
            "name": "AppKey",
            "type": "text"
          },
          {
            "name": "AccessKeyId",
            "type": "text"
          },
          {
            "name": "AccessKeySecret",
            "type": "text"
          }
        ],
        "loginCheckJs": "var response = result;\nif (response.headers().get(\"Content-Type\") != \"audio/mpeg\") {\n    var body = JSON.parse(response.body().string())\n    if (body.status == 40000001) {\n        source.login()\n        java.getHeaderMap().putAll(source.getHeaderMap(true))\n        response = java.getResponse()\n    } else {\n        throw body.message\n    }\n}\nresponse"
      }
    ]
    """#

    /// `assets/defaultData/keyboardAssists.json`.
    static let keyboardAssists = #"""
    [
      {
        "key": "@css:",
        "value": "@css:",
        "serialNo": 0
      },
      {
        "key": "<js>",
        "value": "<js></js>",
        "serialNo": 1
      },
      {
        "key": "{{}}",
        "value": "{{}}",
        "serialNo": 2
      },
      {
        "key": "##",
        "value": "##",
        "serialNo": 3
      },
      {
        "key": "&&",
        "value": "&&",
        "serialNo": 4
      },
      {
        "key": "%%",
        "value": "%%",
        "serialNo": 5
      },
      {
        "key": "||",
        "value": "||",
        "serialNo": 6
      },
      {
        "key": "//",
        "value": "//",
        "serialNo": 7
      },
      {
        "key": "\\",
        "value": "\\",
        "serialNo": 8
      },
      {
        "key": "$.",
        "value": "$.",
        "serialNo": 9
      },
      {
        "key": "@",
        "value": "@",
        "serialNo": 10
      },
      {
        "key": ":",
        "value": ":",
        "serialNo": 11
      },
      {
        "key": "class",
        "value": "class",
        "serialNo": 12
      },
      {
        "key": "text",
        "value": "text",
        "serialNo": 13
      },
      {
        "key": "href",
        "value": "href",
        "serialNo": 14
      },
      {
        "key": "textNodes",
        "value": "textNodes",
        "serialNo": 15
      },
      {
        "key": "ownText",
        "value": "ownText",
        "serialNo": 16
      },
      {
        "key": "all",
        "value": "all",
        "serialNo": 17
      },
      {
        "key": "html",
        "value": "html",
        "serialNo": 18
      },
      {
        "key": "[",
        "value": "[",
        "serialNo": 19
      },
      {
        "key": "]",
        "value": "]",
        "serialNo": 20
      },
      {
        "key": "<",
        "value": "<",
        "serialNo": 21
      },
      {
        "key": ">",
        "value": ">",
        "serialNo": 22
      },
      {
        "key": "#",
        "value": "#",
        "serialNo": 23
      },
      {
        "key": "!",
        "value": "!",
        "serialNo": 24
      },
      {
        "key": ".",
        "value": ".",
        "serialNo": 25
      },
      {
        "key": "+",
        "value": "+",
        "serialNo": 26
      },
      {
        "key": "-",
        "value": "-",
        "serialNo": 27
      },
      {
        "key": "*",
        "value": "*",
        "serialNo": 28
      },
      {
        "key": "/",
        "value": "/",
        "serialNo": 29
      },
      {
        "key": "=",
        "value": "=",
        "serialNo": 30
      },
      {
        "key": "useWebView",
        "value": ",{\"webView\": true}",
        "serialNo": 31
      }
    ]
    """#

    /// `assets/defaultData/coverRule.json`.
    static let coverRule = #"""
    {
      "enable": false,
      "searchUrl": "",
      "coverRule": ""
    }
    """#

    /// `assets/defaultData/directLinkUpload.json`.
    static let directLinkUpload = #"""
    [
      {
        "uploadUrl": "https://sy.nyasama.net/shuyuan,{\"method\":\"POST\",\"body\": {\"file\": \"fileRequest\"},\"type\": \"multipart/form-data\"}",
        "downloadUrlRule": "$.data@js:if (result == '') \n '' \n else \n 'https://shuyuan.nyasama.net/shuyuan/' + result",
        "summary": "喵公子网盘①(有效期30天·香港G口)",
        "compress": false
      },
      {
        "uploadUrl": "https://sy.mgz6.com/shuyuan,{\"method\":\"POST\",\"body\": {\"file\": \"fileRequest\"},\"type\": \"multipart/form-data\"}",
        "downloadUrlRule": "$.data@js:if (result == '') \n '' \n else \n 'https://shuyuan.mgz6.com/shuyuan/' + result",
        "summary": "喵公子网盘②(有效期7天)",
        "compress": false
      },
      {
        "uploadUrl": "http://v2.jt12.eu/up-v2.php,{\"method\":\"POST\",\"body\": {\"file\": \"fileRequest\"},\"type\": \"multipart/form-data\"}",
        "downloadUrlRule": "$.msg",
        "summary": "橘涂书源网盘2.0 Beta(永久有效)",
        "compress": false
      }
    ]
    """#

}
