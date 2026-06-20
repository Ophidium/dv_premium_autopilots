extends "res://ships/ship-ctrl.gd"

func hasFbw() -> bool:
	var type = getConfig("autopilot.type")
	match (type):
		"SYSTEM_AUTOPILOT_MK3":
			return true
		"SYSTEM_AUTOPILOT_MK4":
			return true
		"SYSTEM_AUTOPILOT_RTYPE":
			return true
		"SYSTEM_AUTOPILOT_LIDAR":
			return true
	return false

func autopilotControl(delta, fbw = false):
	if lastDelta == 0:
		return
	var type = getAutopilotType()
	if not cutscene and not isAutopilotPowered():
		if not (ai and randf() < aiPilotingSkill + aiPilotingSkillAdjust):
			inertiaCrawlingAverage = 0
			inertiaObservation = []
			executeThrusterFire(false, delta)
			return
	if type == "SYSTEM_AUTOPILOT_NONE" and not cutscene:
		return
	manualTime = 0

	var solveThrust = false
	var observeRotation = false
	var computeRotation = false
	var drift = getDriftFactor()
	
	var careFactor = 1.0
	if ai:
		if not (aiIsAfraid() or aiIsEngaging()):
			careFactor = clamp(lerp(aiDamagedShipCarefulSpeed, 1.0, getCombatCapacity()), 0, 1)

	match (type):
		"SYSTEM_AUTOPILOT_LIDAR":
			solveThrust = true
			observeRotation = true
			computeRotation = true
		"SYSTEM_AUTOPILOT_RTYPE":
			solveThrust = true
			observeRotation = true
			computeRotation = true
		"SYSTEM_AUTOPILOT_MK1":
			solveThrust = true
			observeRotation = false
			computeRotation = false
		"SYSTEM_AUTOPILOT_MK2":
			solveThrust = true
			observeRotation = true
			computeRotation = false
		"SYSTEM_AUTOPILOT_MK3":
			solveThrust = false
			observeRotation = false
			computeRotation = true
		"SYSTEM_AUTOPILOT_MK4":
			solveThrust = true
			observeRotation = true
			computeRotation = true
			if not ai:
				aiImperativeStrenght = 100.0
				aiImperative = AI.go
				var rotationOverride = autopilotDesiredRotation
				if autopilotVelocityOffsetTarget:
					aiImperativeTarget = autopilotVelocityOffsetTarget
					if Input.is_action_pressed("autopilot_stop"):
						aiImperative = AI.shadow
					else:
						if CurrentGame.isValidCargo(aiImperativeTarget):
							aiImperative = AI.catch
						else:
							aiImperative = AI.watch
				else:
					aiImperative = AI.go
					aiImperativeTarget = null
				if autopilotVectorAdjust or autopilotVelocityOffsetTarget or autopilotHeadingAdjust:
					if not adjustingAI:
						autopilotDesiredVelocity = aiImperativeDirection
						mouseOffsetForAutopilotDesiredVelocity = autopilotDesiredVelocity
						adjustingAI = true
					else:
						aiImperativeDirection = autopilotDesiredVelocity
				else:
					adjustingAI = false

				if not cutscene and not autopilotVectorAdjust and not fbw and not autopilotHeadingAdjust:
					aiControl(lastDelta)
				if autopilotHeadingAdjust:
					autopilotDesiredRotation = rotationOverride
			else:
				adjustingAI = false
				

	

	var offset = Vector2(0, 0)
	if autopilotVelocityOffsetTarget and Tool.claim(autopilotVelocityOffsetTarget):
		offset = autopilotVelocityOffsetTarget.linear_velocity
		Tool.release(autopilotVelocityOffsetTarget)
	else:
		if autopilotVelocityOffsetTarget:
			autopilotDesiredVelocity = linear_velocity
		autopilotVelocityOffsetTarget = null

	var velocityDiffAbs = (autopilotDesiredVelocity + offset) - linear_velocity
	var vel = max(velocityDiffAbs.length() - drift, 0)
	var velocityDiff = Vector2(0, 0)
	if vel > 0:
		velocityDiff = velocityDiffAbs.normalized() * vel * careFactor
	var falloffPower = velocityDiff.length() / autopilotSpeedFalloff

	
	if autopilotComfort and autopilotComfortEnabled:
		autopilotPowerLimit = 1 - clamp((shock - autopilotMaxAcceleration) / autopilotMaxAccelerationMargin, 0, 1) * autopilotPowerLimitAdaptation
		
	else:
		autopilotPowerLimit = 1

	

	var specialRotationOffset = getAutopilotPartOffsetRotation()

	var distance = Tool.angularDistance(autopilotDesiredRotation + specialRotationOffset, rotation)
	var maxVelocity = getMaxRotationVelocity() * careFactor
	var ios = inertiaObservation.size()
	var avf = clamp(1.0 - pow(angularIntegrationFactor, delta * 60), 0, 1)
	integratedAngularVelocity = integratedAngularVelocity * (1 - avf) + angular_velocity * avf
	if abs(lastRotationFireDirection) > 0.05:
		var angularDelta = (lastObservedAngularVelocity - integratedAngularVelocity) / lastDelta
		var observedDelta = max(angularDelta / lastRotationFireDirection, 0)
		
		lastObservedAngularVelocity = integratedAngularVelocity
		if observedDelta > 0:
			inertiaObservation.append(observedDelta)
			inertiaCrawlingAverage += observedDelta
			if ios >= inertiaObservationSampleLength:
				var last = inertiaObservation.pop_front()
				inertiaCrawlingAverage -= last

	var accell = 1.0

	if observeRotation and ios > inertiaObservationMinSampleLength:
		accell = (inertiaCrawlingAverage / ios) / 2

	var mlf = getMaxLeewayFactor()
	var acc = deg2rad(getAutopilotRotationAccurancy())
	var desiredRotationVelocity = min(sqrt(max(0, abs(distance) - acc) * accell * (0.15 + mlf)), maxVelocity) * sign(distance)
	var exactDesiredRotationVelocity = min(sqrt(abs(distance) * accell), maxVelocity) * sign(distance)
	
	var leewayOffset = 0
	if autopilotDesiredAngularVelocity != null:
		desiredRotationVelocity = autopilotDesiredAngularVelocity
		leewayOffset = desiredRotationVelocity

	desiredRotationVelocity += fbwRotationVelocity

	var rvd = abs(desiredRotationVelocity - angular_velocity)
	var rotationPower = clamp(pow(rvd * autopilotRotationAssumption / accell, clamp(delta * 60, 1, 2)), 0, autopilotMaxRotationPower)

	var xrvd = abs(exactDesiredRotationVelocity - angular_velocity)
	var exactRotationPower = clamp(pow(xrvd * autopilotRotationAssumption / accell, clamp(delta * 60, 1, 2)), 0, autopilotMaxRotationPower)


	var rotPri = getRotationPriority()
	var vectorPower = clamp(min(falloffPower, autopilotPowerLimit), 0, autopilotMaxDirectionPower)


	var atf = 0
	
	if angular_velocity > exactDesiredRotationVelocity:
		fireMatching("l", exactRotationPower, true)
	if angular_velocity < exactDesiredRotationVelocity:
		fireMatching("r", exactRotationPower, true)


	if angular_velocity > desiredRotationVelocity:
		atf = rotationPower
		if computeRotation:
			fireRotation( - PI / 2, rotationPower, velocityDiff)
			fireMatching("l", rotationPower, true)
		else:
			fireMatching("l", rotationPower)
		lastRotationFireDirection = rotationPower

	if angular_velocity < desiredRotationVelocity:
		atf = rotationPower
		if computeRotation:
			fireRotation(PI / 2, rotationPower, velocityDiff)
			fireMatching("r", rotationPower, true)
		else:
			fireMatching("r", rotationPower)
		lastRotationFireDirection = - rotationPower

	fireVector(velocityDiff, vectorPower * clamp(1 - atf * rotPri, 0, 1))
	executeThrusterFire(solveThrust, delta)
