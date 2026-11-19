class_name StoryData
extends RefCounted
## 剧情数据。改剧情只改这个文件。
##
## ⚠️ 格式约定（手改时请照抄）：
##   每一行台词 = {"speaker": "说话人", "text": "台词"},
##   · speaker 留空 ""  = 旁白 / 内心独白（不显示名字）
##   · speaker 有内容    = 会话（左上角显示金色名字）
##   · 台词里的双引号要写成 \"
##   · 每行末尾的逗号不能省
##
## 五个剧情段与 BGM：
##   prologue    回家路上 → 进门 → 睡着         Circulation
##   act1_intro  梦中被父母声音包围              Dream Street
##   act1_end    第一段游戏后的剧情（含过渡二）   There's Something Outside
##   act2_end    第二段游戏后的剧情             萍逢
##   epilogue    第三段 → 结局（含信件全文）     萍逢
##
## 游戏流程：
##   prologue → 第一段游戏 → act1_intro → act1_end → 第二段游戏
##   → act2_end → 第三段游戏 → epilogue → 结算
##
## 台词全部来自《游戏总文案(1)(2) (2).docx》，未做删改。
## 想调顺序/删减/加台词，直接改下面每个 "lines" 数组即可。

const SEGMENTS := {
	"prologue": {
		"background": "res://art/story/p1_building.jpg",
		"bgm": "res://audio/bgm/intro_circulation.mp3",
		"lines": [
			{"bg": "res://art/story/p1_building.jpg", "speaker": "", "text": "我今天回家了"},
			{"speaker": "", "text": "从工作的城市赶回了老家"},
			{"speaker": "", "text": "拢共八个小时的路程让我精疲力竭，出租车终于停下来了"},
			{"speaker": "", "text": "到家了"},
			{"speaker": "", "text": "眼前的一切与记忆里的场景重合了，似乎说不出来有什么新变化。"},
			{"speaker": "", "text": "感觉好像是某个放学回家的下午，即使我明明已经离开很长时间了。"},
			{"speaker": "", "text": "我上次回家是什么时候来着…？"},
			{"speaker": "", "text": "（上楼）"},
			{"bg": "res://art/story/p2_stairs.jpg", "speaker": "", "text": "今年贴的对联已经驳落一半了，依稀能看出横批是“马到成功”"},
			{"speaker": "", "text": "好像只有对联换过了，我记得上次走的时候，这个横批是“虎年大吉”"},
			{"speaker": "", "text": "（我习惯性地摸了摸口袋后楞了一会儿，从包里拿出来了一串黄铜钥匙。）"},
			{"speaker": "", "text": "好像是往这边拧……"},
			{"bg": "res://art/story/p3_living.jpg", "speaker": "", "text": "咳咳……味道怎么这么大"},
			{"speaker": "", "text": "（跨进门槛，我注意没有让自己的脏鞋踩到母亲不久前还经常打扫的地板）"},
			{"speaker": "", "text": "（我嗅到了一股家里常年有的霉味，大脑闪过一些模糊的画面）"},
			{"speaker": "", "text": "怎么感觉有点头晕。"},
			{"speaker": "", "text": "（屋内的陈设和我在家的时候差不太多，但屋子里却散发出令人心悸的寂静，我没有觉得孤独，反而有一些莫名的轻松）"},
			{"speaker": "", "text": "父亲两个月前去世时我没回家，我当时太忙了赶不回来，母亲一个人料理了父亲的后事"},
			{"speaker": "", "text": "昨天母亲刚过世，这次我只能回来了，他们走的时候我都不在老家，自然也没见到他们最后一面。"},
			{"speaker": "", "text": "我也说不清自己是因为真的太忙了才一直没有回家，还是因为我其实不太想见到他们。"},
			{"speaker": "", "text": "或许是我不孝吧……每次看见他们，回到这个家，都让我有些紧张不安。"},
			{"bg": "res://art/story/p4_bedroom.jpg", "speaker": "", "text": "（把换下的鞋整整齐齐地摆在门口，轻手轻脚地走进卧室）"},
			{"speaker": "", "text": "（房间和我记忆中一模一样，只是书柜和书桌上已经落了一层薄灰了）"},
			{"speaker": "", "text": "（缓缓坐在床上）"},
			{"speaker": "", "text": "不知是疲劳还是家的味道让我想起了什么"},
			{"speaker": "", "text": "倒在床上让我下意识轻叫了一声"},
			{"speaker": "", "text": "我很快又捂住了嘴巴，害怕父母听到我的声音又跑过来说我不矜持"},
			{"speaker": "", "text": "当我反应过来他们再也不会来管我了的时候，"},
			{"speaker": "", "text": "我突然骂了一句"},
			{"speaker": "", "text": "他妈的"},
			{"speaker": "", "text": "我是疯了吧，没有父母，我不应该呼天抢地，悲痛落泪吗？"},
			{"speaker": "", "text": "至少也要悲伤成疾，看起来垂头丧气的吧"},
			{"speaker": "", "text": "（血液好像充满了我的颅内，我的头有些发热）"},
			{"speaker": "", "text": "管他呢。"},
			{"speaker": "", "text": "我有点困了"},
			{"speaker": "", "text": "（把拖鞋随意甩在地上，一头栽在被子上）"},
			{"speaker": "", "text": "（我突然想起了什么，又爬了起来）"},
			{"speaker": "", "text": "现在我终于可以关上门睡觉了"},
			{"speaker": "", "text": "（累坏了的我很快就睡着了）"},
		],
	},
	"act1_intro": {
		"background": "res://art/story/p5_dream.jpg",
		"bgm": "res://audio/bgm/dream_street.mp3",
		"lines": [
			{"bg": "res://art/story/p5_dream.jpg", "speaker": "", "text": "父母的声音突然出现在我的耳边"},
			{"speaker": "", "text": "谁在说话…你们怎么在这里"},
			{"speaker": "", "text": "好黑......怎么了，家里怎么有奇怪的声音"},
			{"speaker": "", "text": "我睡到晚上了吗？"},
			{"speaker": "", "text": "我求求你们不要再说了，我真的不知道怎么做"},
		],
	},
	"act1_end": {
		"background": "res://art/story/p6_dark.jpg",
		"bgm": "res://audio/bgm/something_outside.mp3",
		"lines": [
			{"bg": "res://art/story/p6_dark.jpg", "speaker": "父母", "text": "这孩子怎么还没起"},
			{"speaker": "父母", "text": "你去看看她是不是又把门锁住了"},
			{"speaker": "父母", "text": "饭都快放凉了"},
			{"speaker": "父母", "text": "昨天晚上肯定又不知道几点睡的"},
			{"speaker": "", "text": "脚步声逐渐贴近，父母的说话声越来越清晰"},
			{"speaker": "", "text": "对着客厅的窗户有个奇怪的黑影走过"},
			{"speaker": "", "text": "房间越来越黑了"},
			{"speaker": "父母", "text": "都说多少遍了不要关门，她老是不听"},
			{"speaker": "父母", "text": "就是啊。"},
			{"bg": "res://art/story/p7_monster.jpg", "speaker": "", "text": "锈迹斑斑的铁门吱呀一声被推到墙上，发出一声巨响"},
			{"speaker": "", "text": "漆黑的门后出现的是一个我闻所未闻的怪物"},
			{"speaker": "", "text": "……"},
			{"speaker": "", "text": "啊！"},
			{"speaker": "", "text": "（我害怕得紧紧缩到被子里）"},
			{"speaker": "", "text": "奇怪，被子什么时候变这么大了"},
			{"speaker": "", "text": "（我摸了摸自己的脸，再看看自己的手）"},
			{"speaker": "", "text": "原来长大只是一场梦吗…"},
			{"speaker": "", "text": "（我探出头，发现怪物已经在向我慢慢靠近了，他的嘴不停说着些什么）"},
			{"speaker": "", "text": "不要！不要！爸爸，妈妈，你们在哪里，我好害怕…"},
			{"speaker": "", "text": "（我被不断的说话声淹没了，那个声音越来越大）"},
			{"speaker": "", "text": "（我拼命捂住耳朵但无济于事）"},
		],
	},
	"act2_end": {
		"background": "res://art/story/room_figure.png",
		"bgm": "res://audio/bgm/pengfeng.mp3",
		"lines": [
			{"speaker": "", "text": "我不明白…"},
			{"speaker": "", "text": "为什么你们爱着我的同时要伤害我"},
			{"speaker": "", "text": "我有时候想，如果我不是你们的孩子就好了"},
			{"speaker": "", "text": "但是我想不出我还能做谁的孩子，没有人像你们一样无条件对我好"},
			{"speaker": "", "text": "我不知道…你们是真的爱我吗"},
			{"speaker": "", "text": "我也想让你们以我为荣"},
			{"speaker": "", "text": "但是我什么都做不好"},
			{"speaker": "", "text": "我心疼你们为我操劳的太多"},
			{"speaker": "", "text": "我不知道是你们亏欠了我还是我辜负了你们"},
			{"speaker": "", "text": "我一直想离开你们，我想逃离这个让我压抑的地方，但是你们给我痛苦的同时也让我体会到幸福"},
			{"speaker": "", "text": "我爱你们，但我的爱里总带着恨和愧疚，这不是完美的爱"},
			{"speaker": "", "text": "…"},
		],
	},
	"epilogue": {
		"background": "res://art/story/e1_bedroom.jpg",
		"bgm": "res://audio/bgm/pengfeng.mp3",
		"lines": [
			{"speaker": "", "text": "（窗帘并没有拉上，我被一条刺眼的阳光耀醒）"},
			{"speaker": "", "text": "妈妈…帮我拉一下窗帘"},
			{"speaker": "", "text": "（在阳光下睁不开眼，挣扎了一会后，突然想到了什么）"},
			{"speaker": "", "text": "不对…"},
			{"speaker": "", "text": "刚刚的是梦吗？"},
			{"speaker": "", "text": "我现在是大人了…但是他们"},
			{"speaker": "", "text": "爸爸妈妈已经去世了"},
			{"speaker": "", "text": "他们死了"},
			{"speaker": "", "text": "刚刚我看到的那些…"},
			{"speaker": "", "text": "（大脑好像被某种东西击打了一般）"},
			{"speaker": "", "text": "他们真的不在了吗…那我该怎么办"},
			{"speaker": "", "text": "可是我们还没有说清楚"},
			{"speaker": "", "text": "是我错怪你们了"},
			{"speaker": "", "text": "他们并没有我想象的那样不堪"},
			{"speaker": "", "text": "我误解的他们一直是我内心的投射"},
			{"speaker": "", "text": "原来我是一直被爱着的"},
			{"speaker": "", "text": "我不知道是该高兴还是该难过"},
			{"speaker": "", "text": "（一阵头皮发麻，颅内因兴奋而涌上头的血变成了沉默的泪，控制不住地流了下来）"},
			{"speaker": "", "text": "为什么我现在才想明白"},
			{"speaker": "", "text": "（无声的抽泣慢慢变成如同受伤般的呜咽）"},
			{"speaker": "", "text": "对不起…没关系…谢谢…"},
			{"speaker": "", "text": "我们好好坐下来，把一切都说清楚好吗？"},
			{"speaker": "", "text": "可是…你们为什么不在了"},
			{"speaker": "", "text": "（我发疯一般在屋里寻找，我想在家里再次找到他们的痕迹）"},
			{"speaker": "", "text": "（我在餐桌的桌布下发现一张我们在大学门口的合照，那似乎是他们留下的少有的照片）"},
			{"photo": "res://art/story/e2_family.jpg", "speaker": "", "text": "（他们的笑容在塑封的照片中永远凝固着）"},
			{"speaker": "", "text": "照片里的你们原来没有那么恐怖"},
			{"speaker": "", "text": "（我拿起照片，正准备仔细看看，发现照片下面鼓鼓囊囊的，好像垫着什么东西）"},
			{"speaker": "", "text": "这是…"},
			{"photo": "", "speaker": "", "text": "（是一封信，署名日期是三年前）"},
			{"speaker": "", "text": "（我双手颤抖着打开）"},
			{"speaker": "父母", "text": "对不起，我的孩子，爸爸妈妈知道小时候亏欠你太多了"},
			{"speaker": "父母", "text": "你现在和我们不亲了，我们也理解"},
			{"speaker": "父母", "text": "我们一直对你要求很严格，也说过很多不好听的话，你小时候也很讨厌这样吧"},
			{"speaker": "父母", "text": "我们也是第一次当父母，我们忘了当初只是想让你开心平安地长大"},
			{"speaker": "父母", "text": "我们发现世界不是这样的，我们不能帮你规避掉所有的困难"},
			{"speaker": "父母", "text": "我们希望你以后变成一个顶天立地的人"},
			{"speaker": "父母", "text": "因为爸爸妈妈不能一直照顾你，所以我们想让你学会好好照顾自己"},
			{"speaker": "父母", "text": "但是我们后来才发现，我们给了你太大的压力"},
			{"speaker": "父母", "text": "我们想弥补你的时候，发现已经来不及了，你已经长大了，我们也做错很多年了。"},
			{"speaker": "父母", "text": "爸爸妈妈知道你不想见我们，我们也不勉强你回来，你过好自己的生活就可以"},
			{"speaker": "父母", "text": "你不用原谅我们，你可以讨厌我们…恨我们"},
			{"speaker": "父母", "text": "但是我们为你骄傲，一直都是…我们从来没有觉得你比别人差…"},
			{"speaker": "", "text": "（泪水在眼眶里渐渐模糊视线，我用手去擦，反而越擦越多，很多字都看不清了）"},
			{"speaker": "父母", "text": "冰箱里……饺子……冻……"},
			{"speaker": "父母", "text": "等你……回来……"},
			{"speaker": "", "text": "（最后一句特别显眼）"},
			{"speaker": "父母", "text": "爸爸妈妈……爱你……对不起……"},
			{"speaker": "", "text": "我不恨你们了"},
			{"speaker": "", "text": "我原谅你们，你们也原谅我好吗？"},
			{"speaker": "父母", "text": "我们从来没有怪过你"},
			{"speaker": "", "text": "一个声音在我脑中响起了"},
			{"speaker": "", "text": "是你们告诉我的吗，我真的听见了"},
		],
	},
}


static func segment(story_id: String) -> Dictionary:
	if SEGMENTS.has(story_id):
		return SEGMENTS[story_id]
	return {}


static func has_segment(story_id: String) -> bool:
	return SEGMENTS.has(story_id)
