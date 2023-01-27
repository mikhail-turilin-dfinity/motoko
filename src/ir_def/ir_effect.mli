open Source
open Mo_types.Type

val is_async_call : Ir.prim -> Ir.exp list -> bool

val max_eff : eff -> eff -> eff

(* (incremental) effect inference on IR *)

val typ : ('a, Note.t) annotated_phrase -> typ
val eff : ('a, Note.t) annotated_phrase -> eff

val is_triv : ('a, Note.t) annotated_phrase -> bool

val effect_exp: Ir.exp -> eff

val infer_effect_prim : Ir.prim -> Ir.exp list -> eff
val infer_effect_exp : Ir.exp -> eff
val infer_effect_dec : Ir.dec -> eff
val infer_effect_decs : Ir.dec list -> eff
