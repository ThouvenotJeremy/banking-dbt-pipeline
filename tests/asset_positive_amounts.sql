-- Test custom : aucun montant négatif dans mart_client_exposure
-- En banque privée une position négative = short selling
-- Ce portefeuille ne fait pas de short selling
select *
from {{ ref('mart_client_exposure') }}
where mt_ast < 0
   or mt_ast_ref < 0