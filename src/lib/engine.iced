
util = require './util'
{config} = require './config'
derive = require './derive'
doc = require './document'

##=======================================================================

class Cache
  constructor : () ->
    @_c = {}
    @_poke()

  _poke : () ->
    @_last_access = util.unix_time()

  lookup : (sio) ->
    k = sio.unique_id()
    obj = @_c[k] = sio unless (obj = @_c[k])?
    return obj

  start : () ->
    console.log "starting background timer loop; write me!"
  
##=======================================================================

input_trim = (x) ->
  rxx = /^(\s*)(.*?)(\s*)$/
  m = x.match rxx
  m[2]
  
input_clean = (x) ->
  ret = input_trim(x).toLowerCase()
  ret = null if ret.length is 0
  ret

##=======================================================================

class VersionObj
  constructor : (args)->
  
  @make : (v, args) ->
    switch v
      when 1 then new Version1Obj args
      when 2 then new Version2Obj args
      else null
      
##-----------------------------------------------------------------------

class Version1Obj extends VersionObj

  constructor : (@_args) ->
  
  clean_passphrase : (pp) ->
    # Replace any interior whitepsace with just a single
    # plain space, but otherwise, interior whitespaces count
    # as part of the passphrase
    input_trim(pp).replace /\s+/g, " "

  key_fields : -> [ 'email', 'passphrase', 'host', 'generation', 'secbits' ]
  derive_key : (input, kgh, cb) -> (new derive.V1 input).run kgh, cb
  
##-----------------------------------------------------------------------

class Version2Obj extends VersionObj

  constructor : (@_args) ->
    
  clean_passphrase : (pp) ->
    # strip out all spaces!
    pp.replace /\s+/g, ""
    
  key_fields : -> [ 'email', 'passphrase', 'secbits' ]
  derive_key : (input, kgh, cb) -> (new derive.V2 input).run kgh, cb
        
##=======================================================================

class Input
  
  constructor : (@_main) ->
    @_unique_id = null
    
  #-----------------------------------------
  
  get : (k) -> @[k]
  set : (k,v) -> @[k] = v
  get_version_obj : () -> VersionObj.make @get 'version'

  #-----------------------------------------
  
  # Serialize the input and assigned it a unique ID
  unique_id : () ->
    unless @_unique_id?
      @_unique_id = (@get f for f in @get_version_obj().key_fields()).join ";" 
    @_unique_id

  #-----------------------------------------
  
  derive_key : (cb) ->
    # the compute hook is called once per iteration in the inner loop
    # of key derivation.  It can be used to stop the derivation (by returning
    # false) and also to report progress to the UI
    compute_hook = (i) =>
      if (ret = @unique_id() is @_main._ri.unique_id())
        if i % 10 is 0 then @_main._doc.show_computing i
      ret

    @get_version_obj().derive_key @, compute_hook, cb

##=======================================================================

exports.RawInput = class RawInput extends Input
  
  constructor : (main) ->
    super main
    @_key = null
    SELECT = [ false, null ]
    @_template =
      email :  [ true, (x) -> input_clean x ]
      passphrase : [ true, (x) => @_clean_passphrase x ]
      host : [ true, (x) -> input_clean x ]
      version : SELECT
      secbits : SELECT
      nsym : SELECT
      generation : SELECT
      length : SELECT

  #-----------------------------------------

  get : (k) ->
    ret = if not (p = @_template[k])? then null
    else if not p[0] then parseInt @_main._doc.q(k).value, 10
    else @[k]
    ret
  
  #-----------------------------------------

  _clean_passphrase : (pp) -> @get_version_obj().clean_passphrase pp

  #-----------------------------------------
  
  set : (k, v) ->
    @_unique_id = null
    if not (p = @_template[k])? then null
    else if p[1] then @[k] = p[1](v)
    else (@[k] = v)
    
  #-----------------------------------------

  sanitize : () ->
    si = new SanitizedInput @_main
    for k of @_template
      if not (v = @get k)?
        return null
      si[k] = v
    si

##=======================================================================

exports.SanitizedInput = class SanitizedInput extends Input
  constructor : (main) ->
    super main

##=======================================================================

class BrowserInfo

##=======================================================================

exports.Engine = class Engine
  
  ##-----------------------------------------

  constructor : (@_doc) ->
    @_cache = new Cache
    @_bi = new BrowserInfo()
    @_ri = new RawInput @

  ##-----------------------------------------

  start : () ->
    @_cache.start()

  ##-----------------------------------------

  got_input : (event) ->
    se = event.srcElement
    @_ri.set se.id, se.value
    @maybe_run()

  ##-----------------------------------------

  run : () ->

    # If we already had an object for this input, grab that instead.
    # Otherwise, we'll add this one to cache...
    @_si = @_cache.lookup @_si

    await @_si.derive_key defer dk

    @_doc.set_generated_pw dk if dk
    
  ##-----------------------------------------

  maybe_run : () ->
    @run() if (@_si = @_ri.sanitize())?
    
##=======================================================================
