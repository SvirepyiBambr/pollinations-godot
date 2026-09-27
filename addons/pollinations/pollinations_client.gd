# Pollinations client for Godot 4 — text, image and speech generation.
# BYOP: every generation is billed to the API key's own Pollen account.
# Set Pollinations.api_key before first use (https://enter.pollinations.ai/keys).
class_name Pollinations

static var api_key: String = ""
static var base_url: String = "https://gen.pollinations.ai"
static var text_model: String = "openai"
static var image_model: String = "flux"
static var speech_model: String = "openai-audio"
static var voice: String = "alloy"


## Single-prompt text completion. Returns the reply text.
static func generate_text(prompt: String, system: String = "", model: String = "") -> String:
	var messages: Array = []
	if system != "":
		messages.append({"role": "system", "content": system})
	messages.append({"role": "user", "content": prompt})
	return await chat(messages, model)


## Full chat completion over an arbitrary message list:
## [{"role": "user", "content": "..."}, ...]
static func chat(messages: Array, model: String = "") -> String:
	var body := {"model": model if model != "" else text_model, "messages": messages}
	var json: Dictionary = await _post_json(
		base_url + "/v1/chat/completions", JSON.stringify(body))
	var choices = json.get("choices", [])
	if choices.is_empty():
		push_error("Pollinations: empty completion")
		return ""
	return choices[0].get("message", {}).get("content", "")


## Generates an image and returns it as an ImageTexture
## (caller decides where to put it; the texture is valid immediately).
static func generate_image(prompt: String, width: int = 1024, height: int = 1024, model: String = "") -> ImageTexture:
	var body := {
		"model": model if model != "" else image_model,
		"prompt": prompt,
		"size": "%dx%d" % [width, height],
	}
	var json: Dictionary = await _post_json(
		base_url + "/v1/images/generations", JSON.stringify(body))
	var data: Array = json.get("data", [])
	if data.is_empty():
		push_error("Pollinations: no image in response")
		return null
	var png: PackedByteArray
	if data[0].has("b64_json"):
		png = Marshalls.base64_to_raw(data[0]["b64_json"])
	elif data[0].has("url"):
		png = await _get_bytes(String(data[0]["url"]))
	else:
		push_error("Pollinations: no image payload")
		return null
	var image := Image.new()
	if image.load_png_from_buffer(png) != OK:
		push_error("Pollinations: invalid PNG payload")
		return null
	return ImageTexture.create_from_image(image)


## Text-to-speech; returns raw audio bytes (wav/mp3 per the model).
static func generate_speech(text: String, voice_override: String = "", model: String = "") -> PackedByteArray:
	var body := {
		"model": model if model != "" else speech_model,
		"voice": voice_override if voice_override != "" else voice,
		"input": text,
	}
	return await _post_bytes(base_url + "/v1/audio/speech", JSON.stringify(body))


# ---- plumbing -----------------------------------------------------------

static func _headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	return headers


static func _post_json(url: String, body: String) -> Dictionary:
	var raw: PackedByteArray = await _post_bytes(url, body)
	if raw.is_empty():
		return {}
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	push_error("Pollinations: unexpected response shape")
	return {}


static func _post_bytes(url: String, body: String) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = 120.0
	Engine.get_main_loop().root.add_child(http)
	var response: Array = await _request(http, url, HTTPClient.METHOD_POST, body.to_utf8_buffer())
	http.queue_free()
	return _unwrap_response(response)


static func _get_bytes(url: String) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = 120.0
	Engine.get_main_loop().root.add_child(http)
	var response: Array = await _request(http, url, HTTPClient.METHOD_GET, PackedByteArray())
	http.queue_free()
	return _unwrap_response(response)


static func _request(http: HTTPRequest, url: String, method: int, body: PackedByteArray) -> Array:
	var err := http.request_raw(url, _headers(), method, body)
	if err != OK:
		push_error("Pollinations: request_raw failed (%s)" % str(err))
		return [err]
	var payload: Array = await http.request_completed
	return payload


static func _unwrap_response(response: Array) -> PackedByteArray:
	# HTTPRequest.request_raw awaits [result, response_code, headers, body]
	if response.is_empty() or response[0] != HTTPRequest.RESULT_SUCCESS:
		push_error("Pollinations: request failed")
		return PackedByteArray()
	if response.size() > 1 and response[1] >= 400:
		push_error("Pollinations: HTTP %s" % str(response[1]))
		return PackedByteArray()
	return response[response.size() - 1]
