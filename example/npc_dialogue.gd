# Sample: talk to an NPC with Pollinations text generation.
# Attach to a Node, set Pollinations.api_key, run the scene and the NPC
# answers in-character with a rolling conversation memory.
extends Node

var persona := "A friendly blacksmith in a small mountain village."
var memory: Array = []


func _ready() -> void:
	var reply := await say("Hello, who are you?")
	print("NPC: ", reply)


func say(player_line: String) -> String:
	memory.append({"role": "user", "content": player_line})
	var context: Array = [{"role": "system", "content": persona +
		" Reply in one or two short sentences, stay in character."}]
	context.append_array(memory)
	var reply := await Pollinations.chat(context)
	memory.append({"role": "assistant", "content": reply})
	while memory.size() > 8:
		memory.pop_front()
	return reply
