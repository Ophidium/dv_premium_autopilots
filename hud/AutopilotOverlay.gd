extends "res://hud/AutopilotOverlay.gd"


func _draw():
	if not is_inside_tree():
		return
	if ship.cutscene:
		return
	if busy.try_lock() == OK:
		var cam = ship.get_global_transform_with_canvas()
		var center = cam.origin
		var ocenter = center
		var velOffset = Vector2(0, 0)
		
		var circleSize = overcircle + pow(1 - engagement, 2) * engagementExpansion
		var circleColor = autopilotEngagedColor * engagement + autopilotDisengagedColor * (1 - engagement)
		draw_circle_arc(center, circleSize, 0, 360, circleColor)
			
		var lidarNode = ship.lidar
		if boresightShapes:
			drawBoresight()
		if lidarNode and autopilotType == "SYSTEM_AUTOPILOT_LIDAR":
			drawLidarBlip(lidarNode, cam)
			drawLidar(lidarNode, center, overcircle, lidarSize)
		if lidarNode and autopilotType == "SYSTEM_AUTOPILOT_MK1":
			drawLidarBlip(lidarNode, cam)
		if lidarNode and autopilotType == "SYSTEM_AUTOPILOT_MK2":
			drawLidar(lidarNode, center, overcircle, lidarSize)
		if ship.trajectoryTarget:
			drawLidarProximity(lidarNode, cam)
		drawHitWarn()
		if droneType == "SYSTEM_RD_GUIDING":
			drawGuidePath()
		if pathShape:
			drawRacingPrediction()
		drawSweep()
		
		var possible = ship.autopilotPossibleTarget
		if Tool.claim(possible):
			var cocenter = possible.get_global_transform_with_canvas().origin
			var s = 1 - (offsetTargetNow / offsetTargetTime)
			for i in range(offsetTargetSteps):
				var c = possibleColor
				if i == 0:
					c = possibleColor * s + autopilotDisengagedColor * (1 - s)
				if i == offsetTargetSteps - 1:
					c = possibleColor * (1 - s) + autopilotDisengagedColor * (s)
				draw_circle_arc(cocenter, (s + i + 1) * offsetTargetScale, 0, 360, c, 3)
			Tool.release(possible)
			
		if ship.trajectoryTarget:
			var ttp = ocenter + (ship.trajectoryTarget.get("init", Vector2(0, 0))) / maxVelocity * overcircle
			var s = 1 - (offsetTargetNow / offsetTargetTime)
			var vel = ship.linear_velocity - velOffset
			var cp = ocenter + (vel / maxVelocity) * overcircle
			for i in range(offsetTargetSteps):
				var dc = autopilotEngagedColor
				if i == 0:
					dc = autopilotEngagedColor * s + autopilotDisengagedColor * (1 - s)
				if i == offsetTargetSteps - 1:
					dc = autopilotEngagedColor * (1 - s) + autopilotDisengagedColor * (s)
				var p = (s + float(i)) / float(offsetTargetSteps)
				draw_circle_arc(lerp(ttp, cp, p), lerp(16 + (ship.getTrajectoryVelocityDeadzone() / 10.0), 16, p), 0, 360, [dc, Color(0, 0, 0, 0)], 6)
			
		if not ship.autopilot:
			var vel = ship.linear_velocity
			var cp = ocenter + (vel / maxVelocity) * overcircle
			var f = clamp(manualOverlayVisibility + engagement, 0, 1)
			var c = autopilotDisengagedColor * (1 - f) + autopilotEngagedColor * f
			
			draw_polyline_colors(PoolVector2Array([ocenter, cp]), PoolColorArray([autopilotDisengagedColor, c]))
			draw_circle_arc(cp, 16, 0, 360, c, 4)
			
			if autopilotMarker:
				autopilotMarker.target = null
		else:
			var offset = ship.autopilotVelocityOffsetTarget
			if Tool.claim(offset):
				var sxf = ship.get_canvas_transform()
				var gtp = ship.getAutopilotTargetGlobalPosition()
				ocenter = sxf.xform(gtp)
				
				velOffset = offset.linear_velocity
				var s = 1 - (offsetTargetNow / offsetTargetTime)
				for i in range(offsetTargetSteps):
					var c = autopilotEngagedColor
					if i == 0:
						c = autopilotEngagedColor * s + autopilotDisengagedColor * (1 - s)
					if i == offsetTargetSteps - 1:
						c = autopilotEngagedColor * (1 - s) + autopilotDisengagedColor * (s)
					draw_circle_arc(ocenter, (s + i + 1) * offsetTargetScale, 0, 360, c, 3)
				if autopilotMarker:
					autopilotMarker.target = offset
					autopilotMarker.targetPosition = gtp
				Tool.release(offset)
			else:
				if autopilotMarker:
					autopilotMarker.target = null
			
			var dvel = ship.autopilotDesiredVelocity
			var avel = ship.aiImperativeDirection
			var vel = ship.linear_velocity - velOffset
			
			var tp = ocenter + (dvel / maxVelocity) * overcircle
			var cp = ocenter + (vel / maxVelocity) * overcircle
			var ap = ocenter + (avel / maxVelocity) * overcircle
			
			draw_circle_arc(tp, 16, 0, 360, [autopilotAdjustingColor, autopilotAdjustingColor2] if ship.autopilotVectorAdjust else autopilotEngagedColor, 8)
			if ship.aiImperativeStrenght > 0 and not ship.aiTarget:
				draw_circle_arc(ap, 16, 0, 360, [autopilotAdjustingColor, autopilotAdjustingColor2] if ship.autopilotVectorAdjust else autopilotEngagedColor, 6)
				draw_line(tp, ap, autopilotEngagedColor, 1.0, true)
				
				
				
			if aiPaths:
				drawAiPaths(ocenter, tp, velOffset)
			if aiSpikes:
				drawAiSpikes()
			if aiAwareness:
				drawAiAwareness()
				
				
			draw_circle_arc(cp, 16, 0, 360, autopilotEngagedColor, 4)
			draw_polyline_colors(PoolVector2Array([ocenter, cp]), PoolColorArray([autopilotDisengagedColor, autopilotEngagedColor]))
			draw_line(cp, tp, autopilotEngagedColor, 1.0, true)
			
			var drot = ship.autopilotDesiredRotation
			var rot = ship.getAutopilotAdjustedHeading()
			var sweep = Vector2(0, - 1)
			
			var rd = Tool.angularDistance(drot, rot)
			var step = 2 * PI / steps
			var sr = rot
			var dist = abs(rd)
			var s
			
			s = sweep.rotated(drot)
			draw_line(center + s * directionTargetStart, center + s * directionEnd, autopilotAdjustingColor if ship.autopilotHeadingAdjust else autopilotEngagedColor, width, true)
			
			s = sweep.rotated(rot)
			draw_line(center + s * directionStart, center + s * directionEnd, autopilotEngagedColor, width, true)

			var points = []
			var colors = []
			
			var d = dist
			while d > step:
				if rd > 0:
					sr += step
				else:
					sr -= step
				d = abs(Tool.angularDistance(drot, sr))
				
				
				s = sweep.rotated(sr)
				points.append(center + s * directionStart)
				points.append(center + s * directionEnd)
				var c = directionColor * (dist - d) * contrast
				colors.append(c)
				colors.append(c)
			if points.size() > 1:
				draw_multiline_colors(points, colors, markWidth, true)
		busy.unlock()
