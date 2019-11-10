;*DECLARATIONS*
extensions [ gis csv nw pathdir ]
breed [ nodes node ]
breed [ bikes bike ]
breed [ cars car ]
turtles-own [
  ;speed
  speed speedMax speedMin speedLimitHere roadNameHere
  ;navigation
  current-location next-node destination energy on-bike-path?
  ;memory
  memory timenow init.AS new.AS newv
]
bikes-own [
  age male density mhl-bike? helmet? motivated? ex-mins METS exposure ]
cars-own [
  collisions interactions ]
nodes-own [
  occupied nodeName ]
links-own [
  roadName weight speedLimit bikePath bikePathWeight ]
globals [
  ;model setup
  roads-dataset propPopulation test-mode
  ;pollution
  pop-pollution
  ;event data
  id event-data collisions-total model-data
  ;counters
  interactions-total initial_cars initial_bikes bike-deaths car-deaths hour minute
]
patches-own [
  ;pollution
  pollution init.P new.P p_time
]

;***********   SETUP   ***********

to setup [user?]
  clear-all
  reset-ticks
  ;user chooses model mode
  if user? = 1 [
    let _mode 0
    if behaviorspace-experiment-name = "" [set _mode user-one-of "Mode" ["1) MHL = 1 Trade-Mode = 0" "2) MHL = 0 Trade-Mode = 0" "3) MHL = 1 Trade-Mode = 1" "4) MHL = 0 Trade-Mode = 1" "5) Testing"]]
    if _mode = "1) MHL = 1 Trade-Mode = 0" [set MHL true set trade-mode false]
    if _mode = "2) MHL = 0 Trade-Mode = 0" [set MHL false set trade-mode false]
    if _mode = "3) MHL = 1 Trade-Mode = 1" [set MHL true set trade-mode true]
    if _mode = "4) MHL = 0 Trade-Mode = 1" [set MHL false set trade-mode true]
    if _mode = "5) Testing" [set test-mode 1]
  ]
  if seed != 0 [random-seed seed]

  setup-map
  setup-clock
  setup-data
  place-agents

  ask cars [set-location set-destination check-speed-and-bike-path]
  ask bikes [set-location set-destination check-speed-and-bike-path]
end

to setup-map
  ask patches [ set pcolor white ]
  import-drawing "/maps/map.png"
  gis:load-coordinate-system "/maps/shapemap/TR_ROAD.prj"
  set roads-dataset gis:load-dataset "/maps/shapemap/TR_ROAD.shp"
  gis:set-world-envelope gis:envelope-of roads-dataset
;  gis:set-drawing-color blue
;  gis:draw roads-dataset 3
  ;list of roads for labelling/speed modifiers
  let _roadlabels ["BRUNSWICK" "ALEXANDRA" "NICHOLSON" "JOHNSTON" "HODDLE" "SMITH"]
  let _40kph ["BRUNSWICK" "SMITH" "JOHNSTON"]
  let _60kph ["ALEXANDRA" "HODDLE" "NICHOLSON"]

  foreach gis:feature-list-of roads-dataset [ vector-feature ->
    ;grab road name of vector-feature
    let _roadname gis:property-value vector-feature "ROAD_NAME"
    ;cycle through each vertex lists of each vector feature
    foreach gis:vertex-lists-of vector-feature [ vertex ->
      let previous-turtle nobody
      foreach vertex [point ->
        ;cycle through each point of each vertex - store xy list coordinates
        let location gis:location-of point
        ;some points contain empty lists - check for valid entries
        if not empty? location
        [
          ;locations stored as [x, y]
          let x item 0 location
          let y item 1 location
          ;create a node on each valid point
          let current-node one-of (turtles-on patch x y) with [ xcor = x and ycor = y ]
          if current-node = nobody [
            create-nodes 1 [
              setxy x y
              set shape "circle"
              set hidden? true
              set current-node self
              if member? _roadname _roadlabels [
              ;  set label _roadname
              ]
              set nodeName _roadname
            ]
          ]
          ask current-node [
            ;connect with previous nodes to form road network
            if is-turtle? previous-turtle [
              ;store road name on link if past node was a match
              let z 0
              if nodeName = [nodeName] of previous-turtle [set z 1]
              create-link-with previous-turtle [set hidden? false set color blue set thickness 0.7 if z = 1 [set roadName _roadname]]
            ]
            set previous-turtle self
          ]
        ]
      ]
    ]
  ]

  ;set speed limits and pathing weights
  ;note: removed labels for visual clarity
  ask links with [member? roadName _40kph] [set weight 0.75 set speedLimit 0.6667 set label ""]
  ask links with [member? roadName _60kph] [set weight 0.5 set speedLimit 1 set label ""]
  ask links with [not member? roadName _40kph and not member? roadName _60kph] [set weight 1 set speedLimit 0.5 set label ""]

  ;create bike paths
  make-bike-paths
end

to make-bike-paths
  if bike-paths = true [
    ;set proportion of links green and attach bikePath dummy var
    ;proportion based on link length? total distance of road network vs. total distance of seg cycling network
    ;sum [link-length] of links {total distance of all links}
    ask links [set bikePathWeight 1]
    let propBikePaths 0.07
    ask n-of (round count links * propBikePaths) links [set bikePath 1 set bikePathWeight 0.5 set color green]
    ;randomly generate new bike path until ratio of route distance bike paths : roads is between 0.07 0.075
    let _bikePaths sum [link-length] of links with [bikePath = 1]
    let _roads sum [link-length] of links with [bikePath = 0]
    while [ _bikePaths / _roads < 0.07 or _bikePaths / _roads > 0.075 ] [
      ask links [set bikePath 0 set bikePathWeight 1 set color blue]
      ask n-of (round count links * propBikePaths) links [set bikePath 1 set bikePathWeight 0.5 set color green]
      set _bikePaths sum [link-length] of links with [bikePath = 1]
      set _roads sum [link-length] of links with [bikePath = 0]
    ]
  ]
end

to find-average-bike-path-p
  let average_p []
  repeat 1000 [ask links [set bikePath 0] make-bike-paths set average_p lput (sum [link-length] of links with [bikePath = 1] / sum [link-length] of links with [bikePath = 0]) average_p]
  show mean average_p
end

to place-agents
  ;test mode with easy setup
  let population count nodes
  ifelse test-mode = 1 [
    ;fixed pop
    ask n-of population nodes with [occupied = 0] [ hatch-cars 1 [ setup-car ] set occupied 1 ]
    ask n-of round (population * propCyclists) cars [ set breed bikes setup-bike set-helmet]
    set initial_cars count cars
    set initial_bikes count bikes
  ]
    [
    ifelse Trade-Mode = true [
      ;start at 1 bike then trade with a car every 10 ticks
      ask n-of population nodes with [occupied = 0] [hatch-cars 1 [setup-car] set occupied 1]
      ask one-of cars [set breed bikes setup-bike set-helmet]
      set initial_cars count cars
      set initial_bikes count bikes
    ]
    [
      ;population based on propPopulation list
      let initialPop round (population * item (read-from-string start-at-hour) propPopulation)
      ask n-of (initialPop) nodes with [occupied = 0] [ hatch-cars 1 [ setup-car ] set occupied 1 ]
      ask n-of ceiling (initialPop * propCyclists) cars [ set breed bikes setup-bike set-helmet]
      ;if MHL is off, add additional unmotivated cyclists to system based on MHL effect)
      if MHL = false [
        let mhlBikes (count cars * MHL_effect)
        ask n-of mhlBikes cars [
          set breed bikes setup-mhl-bike
        ]
      ]
      set initial_cars count cars
      set initial_bikes count bikes
    ]
  ]
end

to setup-bike
  ; *appearance*
  set color black set size 2 set shape "person" set hidden? false
  ; *distributions*
  let _age random-normal 37 14.15
  while [(_age < 18) or (_age > 66)] [set _age random-normal 37 14.15] set age precision _age 2
  ifelse random-float 100 > 59.36 [set male 0] [set male 1]
  set ex-mins random-gamma 25 0.167
  set METS random-normal 6.8 1
  while [(METS < 3) or (METS > 10)] [set METS random-normal 6.8 1]
  ; *model properties*
  set speedMax 0.5 set speedMin 0.1 set speed 0.5 set energy random 30
  utility-function expose
end

to setup-mhl-bike
  setup-bike set-location set-destination check-speed-and-bike-path set helmet? 0 set motivated? 0 set mhl-bike? 1
  set color yellow
end

to set-helmet
  ifelse MHL = true [
    ;MHL on
    ifelse random-float 1 <= motivatedWearers [
      set motivated? 1 set helmet? 1]
    [
      ifelse random-float 1 <= Compliance [set motivated? 0 set helmet? 1] [set motivated? 0 set helmet? 0]
    ]
  ]
  [
    ;MHL off
    ifelse random-float 1 <= motivatedWearers [set motivated? 1 set helmet? 1] [set motivated? 0 set helmet? 0]
  ]
end

to setup-car
  ;*appearance*
  set color grey set shape "car" set size 2 set hidden? false
  ;*model properties*
  set speedMax 1 set speedMin 0 set speed 1 set energy random 30
  set memory one-of [1 0] set timenow random memorySpan
  set init.AS initialV
  calculate-care-factor
end

;*DATA MANAGEMENT*
to setup-data
  set id 1
  set event-data (list ["runNo" "ID" "eventTime" "MHL" "BA" "tradeMode" "bikePaths" "p_bikePaths" "bDensity" "numCars" "numBikes" "meanV" "pAware" "helmet" "male" "age"])
  set model-data (list ["runNo" "t" "MHL" "BA" "tradeMode" "bikePaths" "p_bikePaths" "Interactions(t)" "Collisions(t)" "numCars" "pCars" "numBikes" "pBikes" "bDensity" "pHelmet" "meanV" "pAware" "exMins" "METS" "basePM" "bikePM" "age" "male" "numMHLbikes"])
  set pop-pollution 14.3
  set propPopulation []
  file-open "prop population hourly from 12AM to 11PM.txt"
  while [not file-at-end?] [set propPopulation lput file-read propPopulation]
  file-close
end

to store-model-data
  let _runNo behaviorspace-run-number if _runNo = 0 [set _runNo "NA"]
  let _t ticks
  let _MHL MHL ifelse _MHL = true [set _MHL 1] [set _MHL 0]
  let _BA BA ifelse _BA = true [set _BA 1] [set _BA 0]
  let _tradeMode trade-mode ifelse _tradeMode = true [set _tradeMode 1] [set _tradeMode 0]
  let _bikePaths Bike-Paths ifelse _bikePaths = true [set _bikePaths 1] [set _bikePaths 0]
  let _p_bikePaths (sum [link-length] of links with [bikePath = 1] / sum [link-length] of links with [bikePath = 0]) if _p_bikePaths = 0 [set _p_bikePaths "NA"]
  let _interactions count cars with [interactions = 1]
  let _collisions count cars with [collisions = 1 or collisions = 2]
  let _cars count cars
  let _pCars (count cars / (count cars + count bikes))
  let _bikes count bikes
  let _pBikes (count bikes / (count bikes + count cars))
  let _density mean [density] of bikes
  let _pHelmet mean [helmet?] of bikes
  let _meanv mean [ new.AS ] of cars
  let _paware count cars with [memory = 1] / count cars
  let _exmins mean [ex-mins] of bikes
  let _METS mean [METS] of bikes * mean [ex-mins] of bikes
  let _basePM pop-pollution
  let _bikePM mean [exposure] of bikes
  let _age mean [age] of bikes
  let _male mean [male] of bikes
  let _numMHLbikes count bikes with [mhl-bike? = 1]
  set model-data lput (list _runNo _t _MHL _BA _tradeMode _bikePaths _p_bikePaths _interactions _collisions _cars _pCars _bikes _pBikes _density _pHelmet _meanv _paware _exmins _METS _basePM _bikePM _age _male _numMHLbikes) model-data
end

;*********** MOVEMENT ***********

;*UTILITY FUNCTION*
to utility-function
  ifelse breed = bikes [
    ;if no cars around, increase energy - if cars on patch, decrease energy
    if not any? cars-on neighbors4 [ set energy energy + 1 ]
    if energy > 30 [set energy random 30]
    ;no loss to utility function if on a bike path
    if (any? cars-on patch-here and on-bike-path? = 0) [ set energy energy - 3 ]
    ;death bikes - move to a new location (if no unoccupied, just reset energy)
    if energy < 0 [agent-death]
    ;density check
    if count bikes-on patch-here > 0 [ set density (count bikes in-radius 1) ]
  ]
  [
    ;car utility function
  ]
end

to agent-death
  ifelse breed = bikes [
    set bike-deaths bike-deaths + 1
    carefully [move-to one-of nodes with [occupied = 0] setup-bike set-helmet set-location set-destination check-speed-and-bike-path] [set energy random 30]
  ]
  [
    set car-deaths car-deaths + 1
  ]
end

;*NAVIGATION*
to set-location
  ;initialising node location for agents
  set current-location min-one-of nodes [distance myself]
end

to set-destination
  ;ensures that destination is different to current node location
  let test current-location
  nested-set-destination
  while [destination = test] [nested-set-destination]
  ;face next node on path
  if breed = cars [set next-node item 1 [nw:turtles-on-weighted-path-to ([destination] of myself) weight] of current-location]
  if breed = bikes [set next-node item 1 [nw:turtles-on-weighted-path-to ([destination] of myself) bikePathWeight] of current-location]
  face next-node
end

to nested-set-destination
  ;sets destination as a node with a valid pathway along the road network from agents current node location
  set destination one-of [nodes with [is-number? [ nw:distance-to myself ] of myself]] of current-location
end

to check-speed-and-bike-path
  ;set speed limit equal to occupied road and check whether on a bike path
  let _roadHere nobody
  let target next-node
  ask current-location [set _roadHere link-with target]
  set speedLimitHere [speedLimit] of _roadHere
  set on-bike-path? [bikePath] of _roadHere
  ;ensure speed doesn't exceed bounds
  if speed < speedMin [set speed speedMin]
  if speed > speedLimitHere [
    set speed speedLimitHere
    if speed > speedMax [
      set speed speedMax
    ]
  ]
end

to check-patch-ahead
  ;checks if patch ahead is a patch and if it contains a car/bike, match the speed of that agent
  if breed = cars [
    if is-patch? patch-ahead 1 [
      let bike-ahead one-of bikes-on patch-ahead 1
      ifelse bike-ahead != nobody [set speed [speed] of bike-ahead slow-down] [speed-up]
    ]
  ]

  if breed = bikes [
    if is-patch? patch-ahead 1 [
      let turtle-ahead one-of turtles-on patch-ahead 1
      ifelse turtle-ahead != nobody [set speed [speed] of turtle-ahead slow-down] [speed-up]
    ]
  ]
end

to slow-down
  set speed speed - .1
end

to speed-up
  set speed speed + .1
end

to move
  ;if no destination or at destination, set new destination
  if destination = 0 or destination = current-location [
    set-destination
  ]
  ;if any nodes are within 1 patch and they are not the agent's current node (the node they have just traveled from)
  ;set this as the new current-location
  let test-location min-one-of nodes [distance myself]
  if (any? nodes with [distance myself < 1]) and (test-location != current-location) [
    set current-location min-one-of nodes [distance myself]
    ;if at destination, set new destination
    ifelse current-location = destination [
      set-destination
    ]
    [
      ;otherwise, face the next node on the pathway
      if breed = cars [set next-node item 1 [nw:turtles-on-weighted-path-to ([destination] of myself) weight] of current-location]
      if breed = bikes [set next-node item 1 [nw:turtles-on-path-to [destination] of myself] of current-location]
      face next-node
    ]
  ]
  fd speed
end

;*********** COLLISIONS/POLLUTION ***********

;*COLLISIONS*
to collide
  ;check for a bike and whether not on a bike path
  ifelse (any? bikes-here and on-bike-path? = 0) [
    ;interactions counter
    set interactions 1
    set interactions-total interactions-total + 1
    ;check for non-zero speed
    if speed > 0 [
      ;pick closest bike to self
      let _bike min-one-of bikes-here [distance myself]
      ;store helmet status of bike
      let _helmet [helmet?] of _bike
      ;check collision status
      if collision-check _helmet != 0 [
        ;store event data
        let _runNo behaviorspace-run-number if _runNo = 0 [set _runNo "NA"]
        set _helmet [helmet?] of _bike
        let _age [age] of _bike
        let _male [male] of _bike
        let _eventTime ticks
        let _MHL MHL ifelse _MHL = true [set _MHL 1] [set _MHL 0]
        let _BA BA ifelse _BA = true [set _BA 1] [set _BA 0]
        let _bikePaths Bike-Paths ifelse _bikePaths = true [set _bikePaths 1] [set _bikePaths 0]
        let _p_bikePaths (sum [link-length] of links with [bikePath = 1] / sum [link-length] of links with [bikePath = 0]) if _p_bikePaths = 0 [set _p_bikePaths "NA"]
        let _tradeMode trade-mode ifelse _tradeMode = true [set _tradeMode 1] [set _tradeMode 0]
        let _bDensity (mean [density] of bikes)
        let _numCars count cars
        let _numBikes count bikes
        let _meanV (mean [new.AS] of cars)
        let _pAware (count cars with [memory = 1] / count cars)
        let _data (list _runNo id _eventTime _MHL _BA _tradeMode _bikePaths _p_bikePaths _bDensity _numCars _numBikes _meanV _pAware _helmet _male _age)
        set event-data lput _data event-data
        set id id + 1
        set shape "star"
      ]
    ]
  ]
  ;no bikes or zero speed
    [
    set interactions 0
    set collisions 0 set shape "car"
    ]
end

to-report collision-check [i]
  ; check for collisions - collision rate reduces proportaional to new.AS
  ; RCF may alter risk of collision - separate by i (helmet-status)
  ; check if BA active or inactive
  let _BA BA
  ifelse _BA = true [set _BA 1] [set _BA 0]
  ifelse i = 0 [ ;non-helmeted collision
    ifelse (_BA * new.AS) < random-float 1 [set collisions 2 set collisions-total collisions-total + 1 report 2] [set collisions 0 report 0]
  ]
    [ ;helmeted collision - add RCF
    ifelse (_BA * new.AS * (1 + riskCompensationFactor)) < random-float 1 [set collisions 1 set collisions-total collisions-total + 1 report 1] [set collisions 0 report 0]
  ]
end

;*POLLUTION*
  ;POLLUTION NOTES:
  ;baseline pm2.5/10 exposure 14.3 ug/m3
  ;riding amongst traffic increases exposure 15-75% - any car traffic = 15% (0.1 on patch) to saturated = 75% (1.0 on patch)
  ;motor vehicle fleet contributes 31% of pm2.5/10
  ;cyclists minute-ventilation 2.1x higher than cars (mean = 2.1, sd = 0.77 w/ min 1.34 & max 5.3) - just use average /// ignore for now, no good data
  ;linear regression - relative increase in pm2.5/10 = 10.254x + 0.5304

to pollute
  ifelse any? cars-here [
    ;pollution function
    ;set time_i for decay function
    set p_time ticks
    set new.P (count cars-here * 0.1)
    ;pollution is actual patch exposure - init.P measures changes between ticks
    set pollution (init.p + new.p)
    if pollution > 1 [set pollution 1]
    if pollution < 0 [set pollution 0]
    set init.P pollution
  ]
  ;decay function
  [
    ;check time since last car
    if (ticks - p_time) > decay [
      ;pollution fades proportional to breeze
      set pollution (init.p - (init.p * breeze))
      if pollution < 0 [set pollution 0]
      set init.P pollution
    ]
  ]
end

to expose
  ;ventilation of cyclists on average 2.55 times higher than baseline
  let VE-bikes 2.55
  let local-exposure 0
  ;local exposure (when on roads)
  if on-bike-path? = 0 [set local-exposure [pollution] of patch-here]
  ;relative local pollution effect (10.254x + 0.5304)
  let relative-increase (10.254 * local-exposure + 0.5304)
  ;exposure * ///VE ratio///
  set exposure (pop-pollution + relative-increase) * VE-bikes
end

to pollution-population
  ;predict baseline PM levels - 31% of 14.3 = 4.433 (vehicle fleet contribution)
  if trade-mode = true [set pop-pollution (9.867 + (4.433 * (count cars / initial_cars)))]
  if trade-mode = false [set pop-pollution (9.867 + (4.433 * (1 - MHL_effect)))]
end

;*********** BEHAVIOURAL ADAPTATION **************

;*BEHAVIOURAL ADAPTATION*
to calculate-care-factor
  if BA = true [
  ; set delta_V(t) based on V(t[k]) = Bike_Saliency x Road_Saliency x (MaxV - V(t[k-1])) x (Safe_Driving x Capacity)
  if memory = 1 [ set newv ( ( saliencyBike * saliencyRoad ) * (( maxV - init.AS ) * ( safeDriving * selfCapacity )))  ]

  ; ensure change in association doesn't breach bounds
  if newv > maxv [ set newv maxv ]
  if newv < minv [ set newv minv ]

  ; set association strength to delta_V + initial_V
  set new.AS ( init.AS + newv )
  remember
  forget
  reset-initial
  ]
end

to remember
  ;if cars see a bike ahead of them, set memory = 1 and set timenow to current ticks to check against memory span
  ;only applies when on roads, not bike paths
  if (is-patch? patch-ahead 1 and any? bikes-on patch-ahead 1 and on-bike-path? = 0) [ set memory 1 set timenow ticks ]
  if memory = 0 [ set color white ]
  if memory = 1 [ set color red ]
end

to forget
  ; If time since bike seen is greater than memory span, cars forget that they have seen a bike and equation for memory decay follows
  if ( ticks - timenow ) >= memorySpan [
    set memory 0 set new.AS ( new.AS - (new.AS * ( saliencyBike * saliencyRoad )))
  ]
end

to reset-initial
    ; Resets initial association strength to new association strength - init.AS changes from tick to tick (k-1)
    if new.AS <= maxv [ set init.AS ( new.AS ) ]
end

to update-population
  ;compare old population with new expected population
  let popMultiplier (item hour propPopulation)
  let numNodes (count nodes)
  let oldPop (count cars + count bikes)
  let newPop (numNodes * popMultiplier)
  let popChange (newPop - oldPop)
  let blBikes round (newPop * propCyclists)
  let blCars round (newPop * (1 - propCyclists))

  ifelse popChange > 0 [
    ;net gain to population
    ifelse MHL = true [
      let bikesNow count bikes
      let carsNow count cars
      ;mhl active - create bikes and cars to new pop levels
      ask n-of (blBikes - bikesNow) nodes with [occupied = 0] [
        hatch-bikes 1 [setup-bike set-helmet set-location set-destination check-speed-and-bike-path]
        set occupied 1
      ]
      ask n-of (blCars - carsNow) nodes with [occupied = 0] [
        hatch-cars 1 [setup-car set-location set-destination check-speed-and-bike-path]
        set occupied 1
      ]
    ]
    [
      ;MHL inactive - create MHL/non-MHL cyclists and adjust population levels
      let bikesNow (count bikes with [mhl-bike? = 0])
      let mhlExist (count bikes with [mhl-bike? = 1])
      let mhlExpect round (blCars * MHL_effect)
      let mhlNew (mhlExpect - mhlExist)
      let carsNow (count cars)
      let newCars (blCars - carsNow - mhlExpect)

      ;new non-mhl bikes
      ask n-of (blBikes - bikesNow) nodes with [occupied = 0] [
        hatch-bikes 1 [setup-bike set-helmet set-location set-destination check-speed-and-bike-path]
        set occupied 1
      ]
      ;new mhl bikes
      ask n-of mhlNew nodes with [occupied = 0] [
        hatch-bikes 1 [setup-mhl-bike]
        set occupied 1
      ]
      ;new cars
      if newCars > 0 [
        ask n-of newCars nodes with [occupied = 0] [
          hatch-cars 1 [setup-car set-location set-destination check-speed-and-bike-path]
          set occupied 1
        ]
      ]
    ]
  ]
  [
    ;net loss to population
    set popChange abs popChange
    ifelse MHL = true [
      ;MHL active - ask difference between bl and current to die
      let bikesNow count bikes
      let carsNow count cars
      ask n-of (bikesNow - blBikes) bikes [die]
      ask n-of (carsNow - blCars) cars [die]
    ]
    [
      ;MHL inactive - adjust for MHL bike population
      let bikesNow (count bikes with [mhl-bike? = 0])
      let mhlExist (count bikes with [mhl-bike? = 1])
      let mhlExpect round (blCars * MHL_effect)
      let mhlChange (mhlExist - mhlExpect)
      let carsNow count cars

      ask n-of (bikesNow - blBikes) bikes with [mhl-bike? = 0] [die]
      ask n-of mhlChange bikes with [mhl-bike? = 1] [die]
      ask n-of (carsNow - blCars + mhlExpect) cars [die]
    ]
  ]
end

to trade
  ;trade car for bike every n ticks
  let n 10
  if ticks mod n = 0 [
    if count cars > 1 [
      ask one-of cars [set breed bikes setup-bike set-helmet check-speed-and-bike-path]
      pollution-population
    ]
  ]
end

;*TIME*
to setup-clock
  ;only relevant for non-trade mode
  ifelse trade-mode = false [
    ;initialise time at midnight (must include a date - this is arbitrary and not used in the model)
    ;added option for start-at-hour to initialise at a different time of day
    set hour read-from-string start-at-hour set minute 0
    let hourNow hour if hour < 10 [set hourNow (word "0" hour)]
    output-print (word hourNow ":0" minute)
  ]
  [
    output-print "NA"
  ]
end

to update-clock
  if trade-mode = false [
    ;set previous hour as current hour
    let previousHour hour
    ;add one minute every 2 ticks
    if ticks mod 2 = 0 [
      ifelse minute < 59 [set minute minute + 1] [set minute 0 set hour hour + 1]
      let hourNow hour
      let minuteNow minute
      if hourNow < 10 [set hourNow (word "0" hour)]
      if minuteNow < 10 [set minuteNow (word "0" minute)]
      output-print (word hourNow ":" minuteNow)
    ]
    ;check if new hour
    if test-mode != 1 [
      let hourNow hour
      if (hourNow > previousHour) and (hourNow != 24) [
        update-population
      ]
    ]
  ]
end

;*GO COMMAND*
to go
  ;*END CONDITIONS*
  if (ticks = endAtTicks or hour = 24) and trade-mode = false [output stop]
  if count cars <= 1 [output stop]

  ;*RUNNING MODEL*
  ask cars [
    check-patch-ahead
    check-speed-and-bike-path
    move
  ]
  ask bikes [
    check-patch-ahead
    check-speed-and-bike-path
    move
  ]
  ;check for MHL/population effects
  if trade-mode = true [trade]

  ;update occupied nodes
  ask nodes [ifelse (any? cars-here) or (any? bikes-here) [set occupied 1] [set occupied 0]]

  ask bikes [utility-function expose]
  ask cars [collide calculate-care-factor]
  ask patches [pollute]
  store-model-data
  update-clock

  tick
end

;*EXPORT DATA*
to output
  ifelse behaviorspace-experiment-name = "" [
    ;user run models
    let folder remove ":" date-and-time
    pathdir:create (word "output\\" folder)
    csv:to-file (word "/output/" folder "/event-data.csv") event-data
    csv:to-file (word "/output/" folder "/model-data.csv") model-data
    ;export-all-plots (word "/output/" remove ":" date-and-time "plots.csv")
  ]
  [
    ;behaviorspace runs
    pathdir:create (word "C:\\Users\\Ian\\Desktop\\MHL data\\" behaviorspace-experiment-name "\\event-data\\")
    pathdir:create (word "C:\\Users\\Ian\\Desktop\\MHL data\\" behaviorspace-experiment-name "\\model-data\\")
    csv:to-file (word "C:/Users/Ian/Desktop/MHL data/" behaviorspace-experiment-name "/event-data/Run number " behaviorspace-run-number " - " remove ":" date-and-time "-event-data.csv") event-data
    csv:to-file (word "C:/Users/Ian/Desktop/MHL data/" behaviorspace-experiment-name "/model-data/Run number " behaviorspace-run-number " - " remove ":" date-and-time "-model-data.csv") model-data
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
0
10
814
338
-1
-1
6.255
1
10
1
1
1
0
0
0
1
-64
64
-25
25
0
0
1
ticks
30.0

BUTTON
0
340
63
373
setup
setup 1
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

BUTTON
60
340
115
373
NIL
go
T
1
T
OBSERVER
NIL
G
NIL
NIL
1

BUTTON
116
340
171
373
step
go
NIL
1
T
OBSERVER
NIL
V
NIL
NIL
1

SLIDER
1236
434
1408
467
memorySpan
memorySpan
0
50
50.0
1
1
NIL
HORIZONTAL

SLIDER
1236
332
1408
365
initialV
initialV
0
1
0.0
0.1
1
NIL
HORIZONTAL

SWITCH
232
340
335
373
MHL
MHL
0
1
-1000

SLIDER
882
400
1054
433
motivatedWearers
motivatedWearers
0
1
0.63
0.001
1
NIL
HORIZONTAL

SLIDER
882
363
1054
396
compliance
compliance
0
1
0.96
0.001
1
NIL
HORIZONTAL

SLIDER
1059
329
1231
362
selfCapacity
selfCapacity
0
1
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
1059
363
1231
396
safeDriving
safeDriving
0
1
0.8
0.1
1
NIL
HORIZONTAL

SLIDER
1061
395
1233
428
saliencyBike
saliencyBike
0
1
0.8
0.1
1
NIL
HORIZONTAL

SLIDER
1060
429
1232
462
saliencyRoad
saliencyRoad
0
1
0.8
0.1
1
NIL
HORIZONTAL

SLIDER
1237
399
1409
432
maxV
maxV
0
1
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
1236
365
1408
398
minV
minV
0
1
0.0
0.1
1
NIL
HORIZONTAL

SLIDER
1059
465
1233
498
riskCompensationFactor
riskCompensationFactor
-1
1
0.5
0.1
1
NIL
HORIZONTAL

PLOT
981
160
1433
307
Collisions
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count cars with [collisions = 1] + count cars with [collisions = 2]"

PLOT
0
417
200
567
Mean V
NIL
NIL
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"Mean V" 1.0 0 -16777216 true "" "if any? cars [plot mean [ new.AS ] of cars]"
"Aware" 1.0 0 -7500403 true "" "if any? cars [plot count cars with [ memory = 1 ] / count cars ]"

SLIDER
463
340
572
373
propCyclists
propCyclists
0
1
0.13
0.01
1
NIL
HORIZONTAL

BUTTON
174
340
229
373
NIL
output
NIL
1
T
OBSERVER
NIL
O
NIL
NIL
1

PLOT
981
11
1433
157
Interactions
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count cars with [interactions = 1]"

MONITOR
1437
262
1506
307
Collisions
collisions-total
0
1
11

MONITOR
1436
112
1505
157
Interactions
interactions-total
0
1
11

SLIDER
884
497
1056
530
Breeze
Breeze
0
1
0.2
0.05
1
NIL
HORIZONTAL

SLIDER
884
464
1056
497
Decay
Decay
0
50
15.0
1
1
NIL
HORIZONTAL

TEXTBOX
937
310
1087
328
Helmet wearing
11
0.0
1

TEXTBOX
943
441
1091
459
Pollution
11
0.0
1

TEXTBOX
1186
310
1336
328
Behavioural adaptation
11
0.0
1

MONITOR
821
10
899
55
Cars
count cars
0
1
11

MONITOR
821
55
899
100
Bikes
count bikes
0
1
11

SLIDER
881
328
1053
361
MHL_effect
MHL_effect
0
1
0.0
0.005
1
NIL
HORIZONTAL

MONITOR
900
10
978
55
% Helmeted
count bikes with [helmet? = 1] / count bikes * 100
1
1
11

MONITOR
900
54
978
99
% Motivated
count bikes with [motivated? = 1] / count bikes * 100
1
1
11

PLOT
203
417
403
567
PM2.5/10 Exposure
NIL
NIL
0.0
10.0
0.0
30.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if any? bikes [plot mean [exposure] of bikes]"
"pen-1" 1.0 0 -13791810 true "" "plot pop-pollution"

MONITOR
455
567
568
612
Avg. Ex-Mins
mean [ex-mins] of bikes
1
1
11

SWITCH
337
340
460
373
Trade-Mode
Trade-Mode
1
1
-1000

INPUTBOX
1015
556
1114
616
endAtTicks
2880.0
1
0
Number

SWITCH
1411
333
1501
366
BA
BA
1
1
-1000

MONITOR
664
567
776
612
Inc. MET-Minutes
((mean [ex-mins] of bikes * mean [METS] of bikes) * count bikes) - count bikes
1
1
11

PLOT
607
414
807
564
Incremental MET-Minutes
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if any? bikes [plot ((mean [ex-mins] of bikes * mean [METS] of bikes) * count bikes) - count bikes]"

PLOT
406
416
606
566
Exercise-Minutes/Week
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "if any? bikes [plot mean [ex-mins] of bikes]"

MONITOR
253
568
365
613
PM2.5/10 Exposure
mean [exposure] of bikes
2
1
11

MONITOR
51
569
164
614
Mean V
mean [new.AS] of cars
2
1
11

MONITOR
821
242
900
287
Bike Density
mean [density] of bikes
2
1
11

OUTPUT
689
343
811
379
20

MONITOR
821
147
899
192
Population
count cars + count bikes
17
1
11

CHOOSER
582
340
674
385
start-at-hour
start-at-hour
"00" "06" "08" "12" "15" "17" "20"
0

MONITOR
821
194
901
239
pBikes
count bikes / (count bikes + count cars)
2
1
11

INPUTBOX
883
557
1011
617
seed
2.27677566E8
1
0
Number

MONITOR
821
101
899
146
MHL Bikes
count bikes with [mhl-bike? = 1]
17
1
11

TEXTBOX
935
536
1085
554
Model settings
11
0.0
1

SWITCH
337
375
461
408
Bike-Paths
Bike-Paths
0
1
-1000

BUTTON
1243
570
1414
603
NIL
find-average-bike-path-p
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

bike
false
1
Line -7500403 false 163 183 228 184
Circle -7500403 false false 213 184 22
Circle -7500403 false false 156 187 16
Circle -16777216 false false 28 148 95
Circle -16777216 false false 24 144 102
Circle -16777216 false false 174 144 102
Circle -16777216 false false 177 148 95
Polygon -2674135 true true 75 195 90 90 98 92 97 107 192 122 207 83 215 85 202 123 211 133 225 195 165 195 164 188 214 188 202 133 94 116 82 195
Polygon -2674135 true true 208 83 164 193 171 196 217 85
Polygon -2674135 true true 165 188 91 120 90 131 164 196
Line -7500403 false 159 173 170 219
Line -7500403 false 155 172 166 172
Line -7500403 false 166 219 177 219
Polygon -16777216 true false 187 92 198 92 208 97 217 100 231 93 231 84 216 82 201 83 184 85
Polygon -7500403 true true 71 86 98 93 101 85 74 81
Rectangle -16777216 true false 75 75 75 90
Polygon -16777216 true false 70 87 70 72 78 71 78 89
Circle -7500403 false false 153 184 22
Line -7500403 false 159 206 228 205

bike top
true
2
Rectangle -16777216 true false 68 47 83 122
Rectangle -16777216 true false 67 180 82 255
Rectangle -2674135 true false 68 103 83 178
Circle -955883 true true 46 129 58
Circle -2674135 true false 54 112 42
Rectangle -16777216 true false 42 106 92 114
Rectangle -16777216 true false 62 106 112 114
Rectangle -2674135 true false 55 108 96 113
Line -7500403 false 75 99 75 55
Line -7500403 false 74 233 74 189
Line -1 false 63 182 68 155
Line -1 false 88 180 83 157

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

car top
true
0
Polygon -7500403 true true 76 8 44 10 23 25 11 48 7 225 15 270 30 289 75 294 120 291 135 270 144 225 139 47 126 24 106 11
Polygon -1 true false 132 198 117 213 117 138 132 108
Polygon -1 true false 30 270 45 285 105 285 120 270 120 240 30 240
Polygon -1 true false 18 202 33 217 33 142 18 112
Polygon -1 true false 124 33 99 34 100 15
Line -7500403 true 80 171 65 171
Line -7500403 true 90 165 105 165
Polygon -1 true false 44 138 103 137 127 100 105 92 76 88 43 92 21 100
Line -16777216 false 129 92 114 32
Line -16777216 false 15 90 30 30
Polygon -1 true false 19 35 44 36 43 17

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment_run_4_MHL_0.05" repetitions="1" runMetricsEveryStep="true">
    <setup>reset-ticks
setup 0</setup>
    <go>go</go>
    <enumeratedValueSet variable="seed">
      <value value="1788009676"/>
      <value value="-319005078"/>
      <value value="-257418634"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MHL">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Trade-Mode">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Bike-Paths">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="propCyclists">
      <value value="0.08"/>
      <value value="0.13"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MHL_effect">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="compliance">
      <value value="0.91"/>
      <value value="0.96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivatedWearers">
      <value value="0.58"/>
      <value value="0.63"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="riskCompensationFactor">
      <value value="-0.5"/>
      <value value="0"/>
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Breeze">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="BA">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialV">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minV">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="maxV">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="memorySpan">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="selfCapacity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safeDriving">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="saliencyBike">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="saliencyRoad">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Decay">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="start-at-hour">
      <value value="&quot;00&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="endAtTicks">
      <value value="2880"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="test_2" repetitions="8" runMetricsEveryStep="true">
    <setup>reset-ticks
setup 0</setup>
    <go>go</go>
    <enumeratedValueSet variable="initialV">
      <value value="0"/>
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="endAtTicks">
      <value value="2880"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="compliance">
      <value value="0.91"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Trade-Mode">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="start-at-hour">
      <value value="&quot;00&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="saliencyRoad">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minV">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Decay">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MHL">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="seed">
      <value value="1074695416"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="riskCompensationFactor">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safeDriving">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="propCyclists">
      <value value="0.08"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Breeze">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MHL_effect">
      <value value="0.025"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="memorySpan">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="maxV">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="BA">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivatedWearers">
      <value value="0.579"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="selfCapacity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="saliencyBike">
      <value value="0.8"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experimentB-cycling008" repetitions="1" runMetricsEveryStep="true">
    <setup>reset-ticks
setup 0</setup>
    <go>go</go>
    <enumeratedValueSet variable="initialV">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="endAtTicks">
      <value value="2880"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="compliance">
      <value value="0.91"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="start-at-hour">
      <value value="&quot;00&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Trade-Mode">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="saliencyRoad">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minV">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Decay">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MHL">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="seed">
      <value value="-1927204306"/>
      <value value="1457050477"/>
      <value value="1018303069"/>
      <value value="227677566"/>
      <value value="508416331"/>
      <value value="564486731"/>
      <value value="1336047794"/>
      <value value="827008643"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="riskCompensationFactor">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safeDriving">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="propCyclists">
      <value value="0.08"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="memorySpan">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MHL_effect">
      <value value="0"/>
      <value value="0.025"/>
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="BA">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="maxV">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Breeze">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivatedWearers">
      <value value="0.58"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Bike-Paths">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="selfCapacity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="saliencyBike">
      <value value="0.8"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="RCF_Compliance_MW_MHL_0" repetitions="1" runMetricsEveryStep="true">
    <setup>reset-ticks
setup 0</setup>
    <go>go</go>
    <enumeratedValueSet variable="seed">
      <value value="-1927204306"/>
      <value value="1457050477"/>
      <value value="1018303069"/>
      <value value="227677566"/>
      <value value="508416331"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MHL">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Trade-Mode">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Bike-Paths">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="propCyclists">
      <value value="0.13"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MHL_effect">
      <value value="0"/>
      <value value="0.025"/>
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="compliance">
      <value value="0.96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivatedWearers">
      <value value="0.63"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="riskCompensationFactor">
      <value value="-0.5"/>
      <value value="0"/>
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Breeze">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="BA">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialV">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minV">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="maxV">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="memorySpan">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="selfCapacity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safeDriving">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="saliencyBike">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="saliencyRoad">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Decay">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="start-at-hour">
      <value value="&quot;00&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="endAtTicks">
      <value value="2880"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="RCF_Compliance_MW_MHL_1" repetitions="1" runMetricsEveryStep="true">
    <setup>reset-ticks
setup 0</setup>
    <go>go</go>
    <enumeratedValueSet variable="seed">
      <value value="-1927204306"/>
      <value value="1457050477"/>
      <value value="1018303069"/>
      <value value="227677566"/>
      <value value="508416331"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MHL">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Trade-Mode">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Bike-Paths">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="propCyclists">
      <value value="0.13"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="MHL_effect">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="compliance">
      <value value="0.96"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivatedWearers">
      <value value="0.63"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="riskCompensationFactor">
      <value value="-0.5"/>
      <value value="0"/>
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Breeze">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="BA">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initialV">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="minV">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="maxV">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="memorySpan">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="selfCapacity">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safeDriving">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="saliencyBike">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="saliencyRoad">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Decay">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="start-at-hour">
      <value value="&quot;00&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="endAtTicks">
      <value value="2880"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
