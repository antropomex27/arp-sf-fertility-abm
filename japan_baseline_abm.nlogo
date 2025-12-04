;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; JAPAN BASELINE ABM – VERSIÓN 1.0 (NetLogo)
;; Modelo estilizado de energía, estrés y reproducción
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

globals [
  results-file-open?   ;; bandera: tenemos archivo de resultados abierto (sí/no)
]

breed [persons person]

persons-own [
  energy        ;; energía / estado interno (0–1)
  stress        ;; fatiga / carga estructural percibida (0–1)
  omega         ;; capacidad de reciprocidad (0–1)
  coherence     ;; coherencia interna/relacional (0–1)
  red_self      ;; estado interno adicional (0–5)
  age           ;; edad en años
  sex           ;; "M" o "F"
  paired?       ;; ¿está en relación estable?
  n_children    ;; número de hijos
]

patches-own [
  workload      ;; exigencia laboral/contextual (0–1)
  support       ;; apoyo comunitario/familiar (0–1)
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SETUP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all
  
  ;; inicializar bandera del archivo de resultados
  set results-file-open? false
  
  ;; si quieres corridas repetibles mientras calibras:
  ;; random-seed 12345
  
  setup-patches
  setup-persons
  reset-ticks
  
  ;; abrir/crear archivo de resultados y escribir encabezado
  setup-results-file
end


to setup-patches
  ;; variaciones internas (constantes)
  let workload-variation 0.1
  let support-variation 0.1
  
  ask patches [
    ;; workload: alrededor de mean-workload
    let w mean-workload + (random-float (2 * workload-variation) - workload-variation)
    if w < 0 [ set w 0 ]
    if w > 1 [ set w 1 ]
    set workload w * policy-workload-multiplier
    if workload > 1 [ set workload 1 ]
    
    ;; support: alrededor de mean-support
    let sup mean-support + (random-float (2 * support-variation) - support-variation)
    if sup < 0 [ set sup 0 ]
    if sup > 1 [ set sup 1 ]
    set support sup * policy-support-multiplier
    if support > 1 [ set support 1 ]
  ]
end

to setup-persons
  create-persons initial-population [
    setxy random-xcor random-ycor
    set age 18 + random-float 20   ;; 18–38 al inicio
    set sex one-of ["M" "F"]
    
    set energy random-float 1
    set stress random-float 1
    set omega random-float 1
    set coherence random-float 1
    
    ;; estado interno inicial alrededor de la media
    set red_self initial-red-self-mean +
                  (random-float (2 * initial-red-self-variation) - initial-red-self-variation)
    if red_self < 0 [ set red_self 0 ]
    if red_self > 5 [ set red_self 5 ]
    
    set paired? false
    set n_children 0
    
    ;; apariencia opcional
    set shape "person"
    if sex = "F" [ set color pink ]
    if sex = "M" [ set color blue ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LOOP PRINCIPAL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go
  ;; detener si ya no hay personas
  if not any? persons [
    if results-file-open? [
      file-close
      set results-file-open? false
    ]
    stop
  ]
  
  ;; detener si ya llegamos al tick 100
  if ticks >= 100 [
    if results-file-open? [
      file-close
      set results-file-open? false
    ]
    stop
  ]
  
  ;; dinámica principal
  ask persons [
    update-stress
    update-energy
    update-red-self
    interact
    handle-pairing
    handle-reproduction
    age-agent
  ]
  
  ;; avanzar el tiempo
  tick
  
  ;; registrar datos en el CSV
  if results-file-open? [
    file-print (word
      ticks ","
      avg-children-per-female ","
      mean-energy ","
      mean-stress ","
      count persons)
  ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; DINÁMICAS MICRO
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to update-stress
  ;; el estrés sube por carga de trabajo y baja por recuperación básica
  let s-increase ([workload] of patch-here) * 0.02
  let stress-decay 0.03
  set stress stress + s-increase - stress-decay
  
  if stress < 0 [ set stress 0 ]
  if stress > 1 [ set stress 1 ]
end


to update-energy
  ;; la energía baja por desgaste básico + efecto del estrés
  ;; y sube por apoyo social del entorno
  let sup [support] of patch-here
  
  set energy energy
              - base-energy-drain
              - (stress * stress-to-energy-drain)
              + (sup * support-to-energy-gain)
  
  if energy < 0 [ set energy 0 ]
  if energy > 1 [ set energy 1 ]
end

to update-red-self
  ;; estado interno baja si el estrés es crónicamente alto
  ;; y sube ligeramente cuando la energía es alta
  
  if stress > 0.7 [
    set red_self red_self - 0.05
  ]
  if energy > 0.7 [
    set red_self red_self + 0.02
  ]
  
  if red_self < 0 [ set red_self 0 ]
  if red_self > 5 [ set red_self 5 ]
end

to interact
  ;; decisión de intentar interactuar (baja si el estado interno está bajo)
  let p-int base-interaction-prob
  if red_self < red-self-collapse-threshold [
    set p-int p-int * 0.2
  ]
  
  ;; si no pasa el intento de interactuar, salimos
  if random-float 1 >= p-int [
    stop
  ]
  
  ;; buscar un posible partner cercano
  let candidate one-of other persons in-radius interaction-radius
  if candidate = nobody [
    stop
  ]
  
  ;; probabilidad de reciprocidad
  let avg-omega (omega + [omega] of candidate) / 2
  let p-recip base-reciprocity-prob * avg-omega
  
  ;; constantes internas
  let reciprocity-energy-gain 0.1
  let reciprocity-stress-relief 0.03
  let reciprocity-stress-penalty 0.05
  
  ;; interacción exitosa vs fallida
  ifelse random-float 1 < p-recip [
      ;; ÉXITO
      set energy energy + reciprocity-energy-gain
      set stress stress - reciprocity-stress-relief
      set coherence coherence + 0.02

      ask candidate [
        set energy energy + reciprocity-energy-gain
        set stress stress - reciprocity-stress-relief
        set coherence coherence + 0.02
      ]
  ] [
      ;; FRACASO
      set stress stress + reciprocity-stress-penalty
      ask candidate [
        set stress stress + reciprocity-stress-penalty
      ]
  ]
  
  ;; recortar valores
  if stress < 0 [ set stress 0 ]
  if stress > 1 [ set stress 1 ]
  if energy < 0 [ set energy 0 ]
  if energy > 1 [ set energy 1 ]
end


to handle-pairing
  ;; emparejamiento: solo si tiene energía alta y estrés moderado
  if paired? [ stop ]
  if energy < pair-energy-threshold [ stop ]
  if stress > pair-stress-threshold [ stop ]
  
  let candidate one-of other persons in-radius interaction-radius
  if candidate = nobody [ stop ]
  if [paired?] of candidate [ stop ]
  if sex = [sex] of candidate [ stop ] ;; por ahora solo parejas M-F
  
  ;; formar pareja (no guardamos quién es quién, solo estado booleano)
  set paired? true
  ask candidate [ set paired? true ]
end

to handle-reproduction
  ;; solo si está en pareja, con buena energía y bajo estrés
  if not paired? [ stop ]
  if energy < reproduction-energy-threshold [ stop ]
  if stress > reproduction-stress-threshold [ stop ]
  
  ;; probabilidad de reproducción ajustada por estado interno
  let prob base-reproduction-prob
  if red_self < red-self-collapse-threshold [
    set prob prob * 0.3
  ]
  
  ;; contamos hijos solo en agentes femeninos
  if sex = "F" and random-float 1 < prob [
    set n_children n_children + 1
  ]
end

to age-agent
  set age age + 1
  ;; por ahora NO hay muerte por edad
  ;; if age > max-age [ die ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; REPORTERS (para monitores/plots)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to-report mean-energy
  if any? persons [ report mean [energy] of persons ]
  report 0
end

to-report mean-stress
  if any? persons [ report mean [stress] of persons ]
  report 0
end

to-report mean-red-self
  if any? persons [ report mean [red_self] of persons ]
  report 0
end

to-report avg-children-per-female
  let females persons with [sex = "F"]
  if any? females [ report mean [n_children] of females ]
  report 0
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; EXPORTAR DATOS A CSV
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup-results-file
  ;; Si ya había un archivo abierto en otra corrida, lo cerramos
  if results-file-open? [
    file-close
    set results-file-open? false
  ]
  
  ;; nombre del archivo para Japón 
  file-open "japan-baseline-run030.csv"
  set results-file-open? true
  
  ;; Encabezado del CSV
  file-print "tick,fertility,mean-energy,mean-stress,population"
end
