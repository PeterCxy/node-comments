restify = require 'restify'
request = require 'request'
redis = require 'redis'
md5 = require 'md5'
{korubaku} = require 'korubaku'

# Create server
server = restify.createServer
	name: 'comments'
	version: '1.0.0'

server.use restify.acceptParser server.acceptable
server.use restify.queryParser()
server.use restify.bodyParser()

server.get '/newComment', (req, res, next) ->
	newComment req, res
	next()
server.post '/newComment', (req, res, next) ->
	newComment req, res
	next()
server.get '/getComments', (req, res, next) ->
	getComments req, res
	next()

server.listen 23330, ->
	console.log 'server up'

# Redis
db = redis.createClient()

# constants
commentSet = "commentset"
postPrefix = "post-cmts-"

newComment = (req, res) ->
	korubaku (ko) =>
		cmt =
			email: req.params.email
			nick: req.params.nick
			content: req.params.content
			date: req.params.date

		cmt.reply = req.params.reply if req.params.reply
	
		hash = md5 req.params.email

		[_, response, _] = yield request "https://www.gravatar.com/avatar/#{hash}", ko.raw()

		if response.statusCode is 200
			console.log 'Gravatar found.'
			cmt.hash = hash

		[err, id] = yield db.zcard commentSet, ko.raw()
		if err?
			id = 1
		else
			id += 1
		console.log id

		[err] = yield db.zadd commentSet, id, JSON.stringify(cmt), ko.raw()

		if !err?
			setName = "#{postPrefix}#{req.params.post}"
			[err, num] = yield db.zcard setName, ko.raw()
			if err?
				num = 1
			else
				num += 1
			[err] = yield db.zadd setName, num + 1, id, ko.raw()

		res.writeHead 200
		res.write(if !err? then 'OK' else JSON.stringify(err))
		res.end()

getComments = (req, res) ->
	korubaku (ko) =>
		[err, reply] = yield db.zrange "#{postPrefix}#{req.params.post}", 0, -1, ko.raw()
		
		response = []
		map = []

		for r in reply
			r = parseInt r
			[err, [cmt]] = yield db.zrangebyscore commentSet, r, r, ko.raw()
			if !err?
				cmt = JSON.parse cmt
				delete cmt.email
				cmt.id = r
				if (!cmt.reply? or !map[cmt.reply]?)
					response.push cmt
					map[r] = cmt
				else
					orig = map[cmt.reply]
					if !orig.replies?
						orig.replies = []
					orig.replies.push cmt
			else
				console.log err

		res.writeHead 200
		res.write(if !err? then JSON.stringify(response) else JSON.stringify(err))
		res.end()
