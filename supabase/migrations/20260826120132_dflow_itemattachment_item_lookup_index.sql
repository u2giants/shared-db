-- #1453: bound Item Library attachment fetches by their item foreign key.
-- Keep the index narrow: page results have few attachments per item, so sorting
-- the bounded result by attachment_display_name is cheaper than indexing text.

create index if not exists itemattachment_item_num_id_fk_idx
  on dflow."itemAttachment" (item_num_id_fk);

