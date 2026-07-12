# MERGE table column comparison

Date: 2026-07-12
Compared live `designflow` columns vs existing canonical tables on Supabase project `qsllyeztdwjgirsysgai`.

## Summary

| DesignFlow source | Merge target | DF cols | Target cols | Exact | Fuzzy | Missing in target | Extra on target |
|---|---|---:|---:|---:|---:|---:|---:|
| `art_piece` | `plm.art_piece` | 21 | 12 | 4 | 0 | **17** | 8 |
| `artists` | `core.artist` | 11 | 7 | 4 | 0 | **7** | 3 |
| `AuditLog` | `app.activity` | 10 | 11 | 1 | 0 | **9** | 10 |
| `comments` | `app.comment` | 6 | 12 | 1 | 0 | **5** | 11 |
| `customers` | `core.customer` | 21 | 20 | 0 | 0 | **21** | 20 |
| `externalCustomer` | `core.customer` | 40 | 20 | 1 | 0 | **39** | 19 |
| `externalVendor` | `core.factory` | 30 | 10 | 1 | 0 | **29** | 9 |
| `Factory` | `core.factory` | 7 | 10 | 1 | 0 | **6** | 9 |
| `itemAttachment` | `plm.item_attachment` | 21 | 9 | 1 | 0 | **20** | 8 |
| `itemDetail` | `plm.item_detail` | 164 | 9 | 0 | 0 | **164** | 9 |
| `itemHeader` | `plm.item` | 228 | 16 | 0 | 0 | **228** | 16 |
| `LicenseFeedBacks` | `plm.licensing_feedback` | 8 | 8 | 1 | 0 | **7** | 7 |
| `licenseList` | `core.licensor` | 9 | 7 | 0 | 0 | **9** | 7 |
| `licensingStatus` | `plm.licensing_status` | 14 | 13 | 2 | 0 | **12** | 11 |
| `ProdOrderDetail` | `plm.production_order_line` | 54 | 14 | 1 | 0 | **53** | 13 |
| `ProdOrderHeader` | `plm.production_order` | 124 | 13 | 1 | 0 | **123** | 12 |
| `product_category` | `core.product_category` | 7 | 6 | 4 | 0 | **3** | 2 |
| `properties_and_characters` | `core.property` | 8 | 8 | 5 | 0 | **3** | 3 |
| `property_character_associations` | `core.character` | 5 | 8 | 3 | 0 | **2** | 5 |
| `RFQGroup` | `plm.rfq_group` | 6 | 9 | 0 | 0 | **6** | 9 |
| `RFQItem` | `plm.rfq_item` | 115 | 10 | 0 | 0 | **115** | 10 |
| `RFQVendor` | `plm.rfq_vendor` | 26 | 9 | 0 | 0 | **26** | 9 |
| `Roles` | `app.role` | 2 | 6 | 2 | 0 | **0** | 4 |
| `user_notification` | `app.notification` | 8 | 11 | 2 | 0 | **6** | 9 |
| `users` | `app.profile` | 21 | 11 | 3 | 0 | **18** | 8 |
| `vendor` | `core.factory` | 17 | 10 | 0 | 0 | **17** | 10 |
| `vendorGroup` | `core.factory` | 3 | 10 | 2 | 0 | **1** | 8 |

---

## `designflow.art_piece` → `plm.art_piece`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 21 |
| Target columns | 12 |
| Exact name matches | 4 |
| Fuzzy name matches | 0 |
| Missing in target | 17 |
| Extra on target only | 8 |

### Exact matches

`artist_id`, `created_at`, `id`, `updated_at`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `age_group_id` | integer/int4 |
| `art_description` | text/text |
| `art_display_description` | character varying/varchar |
| `art_number` | character varying/varchar |
| `art_source_id` | integer/int4 |
| `art_type_id` | integer/int4 |
| `big_theme_id` | integer/int4 |
| `created_by` | integer/int4 |
| `divisioncode_id` | integer/int4 |
| `is_active` | boolean/bool |
| `licensor_id` | integer/int4 |
| `little_theme_id` | integer/int4 |
| `property_id` | integer/int4 |
| `season_code_id` | integer/int4 |
| `style_guide_id` | integer/int4 |
| `tags` | character varying/varchar |
| `updated_by` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `art_type` | text/text |
| `artist` | text/text |
| `item_id` | uuid/uuid |
| `name` | text/text |
| `raw` | jsonb/jsonb |
| `source_id` | text/text |
| `source_system` | text/text |
| `status` | text/text |

## `designflow.artists` → `core.artist`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 11 |
| Target columns | 7 |
| Exact name matches | 4 |
| Fuzzy name matches | 0 |
| Missing in target | 7 |
| Extra on target only | 3 |

### Exact matches

`created_at`, `id`, `name`, `updated_at`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `art_source_id` | integer/int4 |
| `artist_type_id` | integer/int4 |
| `created_by` | integer/int4 |
| `divisioncode_id` | integer/int4 |
| `email` | text/text |
| `is_active` | boolean/bool |
| `updated_by` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `metadata` | jsonb/jsonb |
| `normalized_name` | text/text |
| `status` | USER-DEFINED/entity_status |

## `designflow.AuditLog` → `app.activity`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 10 |
| Target columns | 11 |
| Exact name matches | 1 |
| Fuzzy name matches | 0 |
| Missing in target | 9 |
| Extra on target only | 10 |

### Exact matches

`id`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `actionDate` | timestamp without time zone/timestamp |
| `actionType` | character varying/varchar |
| `element_id` | character varying/varchar |
| `moduleName` | character varying/varchar |
| `newValue` | text/text |
| `oldValue` | text/text |
| `ref_id_fk` | integer/int4 |
| `user_id_fk` | integer/int4 |
| `username` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `action` | text/text |
| `actor_profile_id` | uuid/uuid |
| `created_at` | timestamp with time zone/timestamptz |
| `payload` | jsonb/jsonb |
| `source_id` | text/text |
| `source_system` | text/text |
| `summary` | text/text |
| `target_id` | uuid/uuid |
| `target_schema` | text/text |
| `target_table` | text/text |

## `designflow.comments` → `app.comment`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 6 |
| Target columns | 12 |
| Exact name matches | 1 |
| Fuzzy name matches | 0 |
| Missing in target | 5 |
| Extra on target only | 11 |

### Exact matches

`id`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `comment` | character varying/varchar |
| `inserted_date` | timestamp with time zone/timestamptz |
| `item_header_id` | integer/int4 |
| `parent_id` | integer/int4 |
| `user_id` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `body` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `created_by_profile_id` | uuid/uuid |
| `metadata` | jsonb/jsonb |
| `source_id` | text/text |
| `source_system` | text/text |
| `target_id` | uuid/uuid |
| `target_schema` | text/text |
| `target_table` | text/text |
| `updated_at` | timestamp with time zone/timestamptz |
| `visibility` | text/text |

## `designflow.customers` → `core.customer`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 21 |
| Target columns | 20 |
| Exact name matches | 0 |
| Fuzzy name matches | 0 |
| Missing in target | 21 |
| Extra on target only | 20 |

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `customers_airbyte_customers_hashid` | text/text |
| `customers_airbyte_emitted_at` | timestamp with time zone/timestamptz |
| `customers_auditlog` | character varying/varchar |
| `customers_code` | character varying/varchar |
| `customers_dilution` | character varying/varchar |
| `customers_email` | character varying/varchar |
| `customers_expire` | character varying/varchar |
| `customers_id` | integer/int4 |
| `customers_lastname` | character varying/varchar |
| `customers_level` | character varying/varchar |
| `customers_logistic_load` | character varying/varchar |
| `customers_logo` | character varying/varchar |
| `customers_name` | character varying/varchar |
| `customers_notes` | character varying/varchar |
| `customers_notificationemail` | character varying/varchar |
| `customers_notificationsms` | character varying/varchar |
| `customers_passw` | character varying/varchar |
| `customers_phonenum` | character varying/varchar |
| `customers_status` | character varying/varchar |
| `customers_subleveladmin` | character varying/varchar |
| `customers_subscription` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `account_owner_profile_id` | uuid/uuid |
| `address` | jsonb/jsonb |
| `chain_type` | text/text |
| `company_type` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `customer_status` | text/text |
| `domain` | text/text |
| `id` | uuid/uuid |
| `is_potential` | boolean/bool |
| `legal_name` | text/text |
| `metadata` | jsonb/jsonb |
| `name` | text/text |
| `normalized_name` | text/text |
| `phone` | text/text |
| `primary_salesperson_profile_id` | uuid/uuid |
| `routing_aliases` | text/text |
| `so_patterns` | text/text |
| `status` | USER-DEFINED/entity_status |
| `updated_at` | timestamp with time zone/timestamptz |
| `website` | text/text |

## `designflow.externalCustomer` → `core.customer`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 40 |
| Target columns | 20 |
| Exact name matches | 1 |
| Fuzzy name matches | 0 |
| Missing in target | 39 |
| Extra on target only | 19 |

### Exact matches

`id`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `active` | character varying/varchar |
| `address1` | character varying/varchar |
| `address2` | character varying/varchar |
| `address3` | character varying/varchar |
| `aRCustomerCode` | character varying/varchar |
| `city` | character varying/varchar |
| `commissionPerc1` | character varying/varchar |
| `commissionPerc2` | character varying/varchar |
| `companyCode` | character varying/varchar |
| `countryCode` | character varying/varchar |
| `createdTime` | character varying/varchar |
| `createdUser` | character varying/varchar |
| `currencyCode` | character varying/varchar |
| `customerCode` | character varying/varchar |
| `customerDBA` | character varying/varchar |
| `customerDesc` | character varying/varchar |
| `customerTypeCode` | character varying/varchar |
| `dsCat` | character varying/varchar |
| `factorCode` | character varying/varchar |
| `faxNo` | character varying/varchar |
| `glCode` | character varying/varchar |
| `modTime` | character varying/varchar |
| `modUser` | character varying/varchar |
| `oldCustomerCode` | character varying/varchar |
| `parentCustomerCode` | character varying/varchar |
| `phoneNo` | character varying/varchar |
| `regionCode` | character varying/varchar |
| `salesPersonCode1` | character varying/varchar |
| `salesPersonCode2` | character varying/varchar |
| `state` | character varying/varchar |
| `udf01` | character varying/varchar |
| `udf02` | character varying/varchar |
| `udf03` | character varying/varchar |
| `udf04` | character varying/varchar |
| `udfDate01` | character varying/varchar |
| `udfDate02` | character varying/varchar |
| `useConsolidatedInvoice` | character varying/varchar |
| `vendorNumber` | character varying/varchar |
| `zipCode` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `account_owner_profile_id` | uuid/uuid |
| `address` | jsonb/jsonb |
| `chain_type` | text/text |
| `company_type` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `customer_status` | text/text |
| `domain` | text/text |
| `is_potential` | boolean/bool |
| `legal_name` | text/text |
| `metadata` | jsonb/jsonb |
| `name` | text/text |
| `normalized_name` | text/text |
| `phone` | text/text |
| `primary_salesperson_profile_id` | uuid/uuid |
| `routing_aliases` | text/text |
| `so_patterns` | text/text |
| `status` | USER-DEFINED/entity_status |
| `updated_at` | timestamp with time zone/timestamptz |
| `website` | text/text |

## `designflow.externalVendor` → `core.factory`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 30 |
| Target columns | 10 |
| Exact name matches | 1 |
| Fuzzy name matches | 0 |
| Missing in target | 29 |
| Extra on target only | 9 |

### Exact matches

`id`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `active` | character varying/varchar |
| `address1` | character varying/varchar |
| `address2` | character varying/varchar |
| `address3` | character varying/varchar |
| `city` | character varying/varchar |
| `companyCode` | character varying/varchar |
| `countryCode` | character varying/varchar |
| `createdTime` | character varying/varchar |
| `createdUser` | character varying/varchar |
| `email` | character varying/varchar |
| `faxNo` | character varying/varchar |
| `femaExpDate` | character varying/varchar |
| `glCode` | character varying/varchar |
| `modTime` | character varying/varchar |
| `modUser` | character varying/varchar |
| `nbcExpDate` | character varying/varchar |
| `payTermCode` | character varying/varchar |
| `phoneNo` | character varying/varchar |
| `separateCheck` | character varying/varchar |
| `state` | character varying/varchar |
| `udf01` | character varying/varchar |
| `udf02` | character varying/varchar |
| `udf03` | character varying/varchar |
| `udf04` | character varying/varchar |
| `udfDate01` | character varying/varchar |
| `udfDate02` | character varying/varchar |
| `vendorCode` | character varying/varchar |
| `vendorDesc` | character varying/varchar |
| `zipCode` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `code` | text/text |
| `company_id` | uuid/uuid |
| `country` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `metadata` | jsonb/jsonb |
| `name` | text/text |
| `status` | USER-DEFINED/entity_status |
| `updated_at` | timestamp with time zone/timestamptz |
| `vendor_group` | text/text |

## `designflow.Factory` → `core.factory`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 7 |
| Target columns | 10 |
| Exact name matches | 1 |
| Fuzzy name matches | 0 |
| Missing in target | 6 |
| Extra on target only | 9 |

### Exact matches

`id`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `factory_access` | character varying/varchar |
| `factory_country` | character varying/varchar |
| `factory_name` | character varying/varchar |
| `factory_nickname` | character varying/varchar |
| `factory_status` | character varying/varchar |
| `sort_order` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `code` | text/text |
| `company_id` | uuid/uuid |
| `country` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `metadata` | jsonb/jsonb |
| `name` | text/text |
| `status` | USER-DEFINED/entity_status |
| `updated_at` | timestamp with time zone/timestamptz |
| `vendor_group` | text/text |

## `designflow.itemAttachment` → `plm.item_attachment`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 21 |
| Target columns | 9 |
| Exact name matches | 1 |
| Fuzzy name matches | 0 |
| Missing in target | 20 |
| Extra on target only | 8 |

### Exact matches

`attachment_type`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `attachment_display_name` | character varying/varchar |
| `attachment_link` | character varying/varchar |
| `comment_id` | integer/int4 |
| `companyCode_name` | character varying/varchar |
| `divisionCode_name` | character varying/varchar |
| `dsn_ref_num` | character varying/varchar |
| `item_attachment_colorCode` | character varying/varchar |
| `item_attachment_createdTime` | character varying/varchar |
| `item_attachment_createdUser` | character varying/varchar |
| `item_attachment_fileName` | character varying/varchar |
| `item_attachment_id` | integer/int4 |
| `item_attachment_modTime` | character varying/varchar |
| `item_attachment_modUser` | character varying/varchar |
| `item_attachment_resourceId` | integer/int4 |
| `item_num_id_fk` | integer/int4 |
| `license_status` | character varying/varchar |
| `licensing_attachment` | boolean/bool |
| `licensing_feedback_id_fk` | integer/int4 |
| `primary_image` | boolean/bool |
| `uuid` | uuid/uuid |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `created_at` | timestamp with time zone/timestamptz |
| `file_object_id` | uuid/uuid |
| `id` | uuid/uuid |
| `item_id` | uuid/uuid |
| `metadata` | jsonb/jsonb |
| `source_id` | text/text |
| `source_system` | text/text |
| `url` | text/text |

## `designflow.itemDetail` → `plm.item_detail`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 164 |
| Target columns | 9 |
| Exact name matches | 0 |
| Fuzzy name matches | 0 |
| Missing in target | 164 |
| Extra on target only | 9 |

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `base_qty_hed` | integer/int4 |
| `carton_code_ext` | character varying/varchar |
| `carton_depth_size_hed` | numeric/numeric |
| `carton_length_size_hed` | numeric/numeric |
| `carton_packtype_fk` | character varying/varchar |
| `carton_qty` | integer/int4 |
| `carton_weight_size_hed` | numeric/numeric |
| `carton_width_size_hed` | numeric/numeric |
| `color_code_fk` | character varying/varchar |
| `compare_price_hed` | numeric/numeric |
| `created_timedate` | timestamp without time zone/timestamp |
| `created_user_fk` | character varying/varchar |
| `dim_code_fk` | character varying/varchar |
| `discont_status` | character varying/varchar |
| `ds_cat` | character varying/varchar |
| `EAN` | character varying/varchar |
| `GenerateUPC` | character varying/varchar |
| `GTIN` | character varying/varchar |
| `hts_num_hed_ext_fk` | character varying/varchar |
| `innerpk_qty_hed` | integer/int4 |
| `item_active_status` | character varying/varchar |
| `item_avail_status` | character varying/varchar |
| `item_cbm_size` | numeric/numeric |
| `item_content_hed` | character varying/varchar |
| `item_cost_hed_ext` | numeric/numeric |
| `item_depth_size_hed` | numeric/numeric |
| `item_length_size_hed` | numeric/numeric |
| `item_pk` | integer/int4 |
| `item_status_hed` | character varying/varchar |
| `item_weight_size_hed` | numeric/numeric |
| `item_width_size_hed` | numeric/numeric |
| `label_code_fk` | character varying/varchar |
| `mod_timedate` | timestamp without time zone/timestamp |
| `mod_user_fk` | character varying/varchar |
| `NMFC_code_hed` | character varying/varchar |
| `non_inv_item` | character varying/varchar |
| `pack_type_hed` | character varying/varchar |
| `prepack_code_fk` | character varying/varchar |
| `reserved_qty` | integer/int4 |
| `retail_pric_hed` | numeric/numeric |
| `royalty_code_fk` | character varying/varchar |
| `salesperson_fk` | character varying/varchar |
| `season_code_hed` | character varying/varchar |
| `selling_price_hed` | numeric/numeric |
| `share_UPC` | character varying/varchar |
| `size_allowed_hed` | character varying/varchar |
| `size_code_fk` | character varying/varchar |
| `size_explo_code_hed_ext` | character varying/varchar |
| `size_seq` | integer/int4 |
| `udf_date01` | timestamp without time zone/timestamp |
| `udf_date02` | timestamp without time zone/timestamp |
| `udf_date03` | timestamp without time zone/timestamp |
| `udf_date04` | timestamp without time zone/timestamp |
| `udf_date05` | timestamp without time zone/timestamp |
| `udf_date06` | timestamp without time zone/timestamp |
| `udf_date07` | timestamp without time zone/timestamp |
| `udf_date08` | timestamp without time zone/timestamp |
| `udf_date09` | timestamp without time zone/timestamp |
| `udf_date10` | timestamp without time zone/timestamp |
| `udf_date11` | timestamp without time zone/timestamp |
| `udf_date12` | timestamp without time zone/timestamp |
| `udf_date13` | timestamp without time zone/timestamp |
| `udf_date14` | timestamp without time zone/timestamp |
| `udf_date15` | timestamp without time zone/timestamp |
| `udf_date16` | timestamp without time zone/timestamp |
| `udf_date17` | timestamp without time zone/timestamp |
| `udf_date18` | timestamp without time zone/timestamp |
| `udf_date19` | timestamp without time zone/timestamp |
| `udf_date20` | timestamp without time zone/timestamp |
| `udf_freeform_01` | character varying/varchar |
| `udf_freeform_02` | character varying/varchar |
| `udf_freeform_03` | character varying/varchar |
| `udf_freeform_04` | character varying/varchar |
| `udf_freeform_05` | character varying/varchar |
| `udf_freeform_06` | character varying/varchar |
| `udf_freeform_07` | character varying/varchar |
| `udf_freeform_08` | character varying/varchar |
| `udf_freeform_09` | character varying/varchar |
| `udf_freeform_10` | character varying/varchar |
| `udf_freeform_11` | character varying/varchar |
| `udf_freeform_12` | character varying/varchar |
| `udf_freeform_13` | character varying/varchar |
| `udf_freeform_14` | character varying/varchar |
| `udf_freeform_15` | character varying/varchar |
| `udf_freeform_16` | character varying/varchar |
| `udf_freeform_17` | character varying/varchar |
| `udf_freeform_18` | character varying/varchar |
| `udf_freeform_19` | character varying/varchar |
| `udf_freeform_20` | character varying/varchar |
| `udf_int01` | integer/int4 |
| `udf_int02` | integer/int4 |
| `udf_int03` | integer/int4 |
| `udf_int04` | integer/int4 |
| `udf_int05` | integer/int4 |
| `udf_int06` | integer/int4 |
| `udf_int07` | integer/int4 |
| `udf_int08` | integer/int4 |
| `udf_int09` | integer/int4 |
| `udf_int10` | integer/int4 |
| `udf_item_priceA` | numeric/numeric |
| `udf_item_priceB` | numeric/numeric |
| `udf_item_priceC` | numeric/numeric |
| `udf_item_priceD` | numeric/numeric |
| `udf_item_priceE` | numeric/numeric |
| `udf_item_priceF` | numeric/numeric |
| `udf_item_priceG` | numeric/numeric |
| `udf_item_priceH` | numeric/numeric |
| `udf_merchgroup01` | character varying/varchar |
| `udf_merchgroup02` | character varying/varchar |
| `udf_merchgroup03` | character varying/varchar |
| `udf_merchgroup04` | character varying/varchar |
| `udf_merchgroup05` | character varying/varchar |
| `udf_merchgroup06` | character varying/varchar |
| `udf_merchgroup07` | character varying/varchar |
| `udf_merchgroup08` | character varying/varchar |
| `udf_merchgroup09` | character varying/varchar |
| `udf_merchgroup10` | character varying/varchar |
| `udf_merchgroup11` | character varying/varchar |
| `udf_merchgroup12` | character varying/varchar |
| `udf_merchgroup13` | character varying/varchar |
| `udf_merchgroup14` | character varying/varchar |
| `udf_merchgroup15` | character varying/varchar |
| `udf_merchgroup16` | character varying/varchar |
| `udf_merchgroup17` | character varying/varchar |
| `udf_merchgroup18` | character varying/varchar |
| `udf_merchgroup19` | character varying/varchar |
| `udf_merchgroup20` | character varying/varchar |
| `udf_merchgroup21` | character varying/varchar |
| `udf_merchgroup22` | character varying/varchar |
| `udf_merchgroup23` | character varying/varchar |
| `udf_merchgroup24` | character varying/varchar |
| `udf_merchgroup25` | character varying/varchar |
| `udf_num01` | numeric/numeric |
| `udf_num02` | numeric/numeric |
| `udf_num03` | numeric/numeric |
| `udf_num04` | numeric/numeric |
| `udf_num05` | numeric/numeric |
| `udf_num06` | numeric/numeric |
| `udf_num07` | numeric/numeric |
| `udf_num08` | numeric/numeric |
| `udf_num09` | numeric/numeric |
| `udf_num10` | numeric/numeric |
| `udf_yesno01` | character varying/varchar |
| `udf_yesno02` | character varying/varchar |
| `udf_yesno03` | character varying/varchar |
| `udf_yesno04` | character varying/varchar |
| `udf_yesno05` | character varying/varchar |
| `udf_yesno06` | character varying/varchar |
| `udf_yesno07` | character varying/varchar |
| `udf_yesno08` | character varying/varchar |
| `udf_yesno09` | character varying/varchar |
| `udf_yesno10` | character varying/varchar |
| `udf_yesno11` | character varying/varchar |
| `udf_yesno12` | character varying/varchar |
| `udf_yesno13` | character varying/varchar |
| `udf_yesno14` | character varying/varchar |
| `udf_yesno15` | character varying/varchar |
| `uom_code_hed_fk` | character varying/varchar |
| `uom_size_fk_hed` | character varying/varchar |
| `uom_weight_fk_hed` | character varying/varchar |
| `UPC` | character varying/varchar |
| `upc_created_timedate` | timestamp without time zone/timestamp |
| `vendor_code_hed_fk` | character varying/varchar |
| `whse_sku_id` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `created_at` | timestamp with time zone/timestamptz |
| `detail_type` | text/text |
| `id` | uuid/uuid |
| `item_id` | uuid/uuid |
| `source_id` | text/text |
| `source_system` | text/text |
| `value_json` | jsonb/jsonb |
| `value_number` | numeric/numeric |
| `value_text` | text/text |

## `designflow.itemHeader` → `plm.item`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 228 |
| Target columns | 16 |
| Exact name matches | 0 |
| Fuzzy name matches | 0 |
| Missing in target | 228 |
| Extra on target only | 16 |

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `AllowedSizes_ext` | character varying/varchar |
| `art_piece_id` | integer/int4 |
| `base_qty` | integer/int4 |
| `carton_code_ext` | character varying/varchar |
| `carton_depth_size` | numeric/numeric |
| `carton_length_size` | numeric/numeric |
| `carton_packtype_fk` | character varying/varchar |
| `carton_qty` | integer/int4 |
| `carton_weight_size` | numeric/numeric |
| `carton_width_size` | numeric/numeric |
| `comm_code_ext` | character varying/varchar |
| `compan_code` | character varying/varchar |
| `compan_code_fk` | integer/int4 |
| `compare_price` | numeric/numeric |
| `costcomp1` | numeric/numeric |
| `costcomp2` | numeric/numeric |
| `costcomp3` | numeric/numeric |
| `costcomp4` | numeric/numeric |
| `costcomp5` | numeric/numeric |
| `created_time_date` | timestamp without time zone/timestamp |
| `created_user_fk` | character varying/varchar |
| `discont_status` | character varying/varchar |
| `div_code` | character varying/varchar |
| `div_code_fk` | integer/int4 |
| `ds_cat` | character varying/varchar |
| `dsn_ref_num` | character varying/varchar |
| `due_date` | timestamp with time zone/timestamptz |
| `giftwrap` | character varying/varchar |
| `hts_num_ext_fk` | character varying/varchar |
| `hts2_num_ext_fk` | character varying/varchar |
| `innerpack_qty` | integer/int4 |
| `is_item_active` | boolean/bool |
| `is_item_old` | boolean/bool |
| `item_active_status` | character varying/varchar |
| `item_avail_status` | character varying/varchar |
| `item_cbm_size` | numeric/numeric |
| `item_content` | character varying/varchar |
| `item_cost_ext` | numeric/numeric |
| `item_depth_size` | character varying/varchar |
| `item_descr_name` | character varying/varchar |
| `item_displ_descr_name` | character varying/varchar |
| `item_id_pk` | integer/int4 |
| `item_length_size` | numeric/numeric |
| `item_note` | character varying/varchar |
| `item_num_id` | character varying/varchar |
| `item_type_id_fk` | integer/int4 |
| `item_weight_size` | numeric/numeric |
| `item_width_size` | numeric/numeric |
| `lic_brand_assurance_number` | character varying/varchar |
| `lic_comment` | character varying/varchar |
| `lic_compnay` | character varying/varchar |
| `lic_concept_approved` | character varying/varchar |
| `lic_concept_approved_date` | character varying/varchar |
| `lic_concept_rejected` | character varying/varchar |
| `lic_concept_rejected_date` | character varying/varchar |
| `lic_concept_submiteed` | character varying/varchar |
| `lic_concept_submitted_date` | character varying/varchar |
| `lic_dev_received` | character varying/varchar |
| `lic_dev_sample_recv_date` | character varying/varchar |
| `lic_dev_sample_sent` | character varying/varchar |
| `lic_dev_sample_sent_date` | character varying/varchar |
| `lic_item_desc` | character varying/varchar |
| `lic_licensorcode` | character varying/varchar |
| `lic_office_received` | character varying/varchar |
| `lic_office_received_date` | character varying/varchar |
| `lic_office_sent` | character varying/varchar |
| `lic_office_sent_date` | character varying/varchar |
| `lic_order_placed` | character varying/varchar |
| `lic_order_placed_date` | character varying/varchar |
| `lic_prepo_approved` | character varying/varchar |
| `lic_prepo_approved_date` | character varying/varchar |
| `lic_prepo_rejected` | character varying/varchar |
| `lic_prepo_rejected_date` | character varying/varchar |
| `lic_sample_made` | character varying/varchar |
| `lic_sample_made_date` | character varying/varchar |
| `lic_sample_no` | character varying/varchar |
| `lic_sample_requested` | character varying/varchar |
| `lic_sample_requested_date` | character varying/varchar |
| `lic_tracking_updated_date` | timestamp with time zone/timestamptz |
| `lic_vendor_sent` | character varying/varchar |
| `lic_vendor_sent_date` | character varying/varchar |
| `mfg_lead_time` | integer/int4 |
| `mod_time_date` | timestamp without time zone/timestamp |
| `mod_user_fk` | character varying/varchar |
| `non_inv_item` | character varying/varchar |
| `OH_min_qty` | integer/int4 |
| `old_item_num` | character varying/varchar |
| `origin_country_fk` | character varying/varchar |
| `pack_type` | character varying/varchar |
| `product_manager_fk` | character varying/varchar |
| `productmanager` | character varying/varchar |
| `ref_num` | character varying/varchar |
| `retail_price` | numeric/numeric |
| `royalty_code_fk` | character varying/varchar |
| `royalty2_code_fk` | character varying/varchar |
| `salesper_code_fk` | character varying/varchar |
| `salesper2_code_fk` | character varying/varchar |
| `sample_start_date` | character varying/varchar |
| `season_code_fk` | character varying/varchar |
| `season_code_fk_id` | integer/int4 |
| `selling_price` | numeric/numeric |
| `size_explo_code_ext` | character varying/varchar |
| `size_range_code_ext` | character varying/varchar |
| `tags` | character varying/varchar |
| `udf_date01` | timestamp without time zone/timestamp |
| `udf_date02` | timestamp without time zone/timestamp |
| `udf_date03` | timestamp without time zone/timestamp |
| `udf_date04` | timestamp without time zone/timestamp |
| `udf_date05` | timestamp without time zone/timestamp |
| `udf_date06` | timestamp without time zone/timestamp |
| `udf_date07` | timestamp without time zone/timestamp |
| `udf_date08` | timestamp without time zone/timestamp |
| `udf_date09` | timestamp without time zone/timestamp |
| `udf_date10` | timestamp without time zone/timestamp |
| `udf_date11` | timestamp without time zone/timestamp |
| `udf_date12` | timestamp without time zone/timestamp |
| `udf_date13` | timestamp without time zone/timestamp |
| `udf_date14` | timestamp without time zone/timestamp |
| `udf_date15` | timestamp without time zone/timestamp |
| `udf_date16` | timestamp without time zone/timestamp |
| `udf_date17` | timestamp without time zone/timestamp |
| `udf_date18` | timestamp without time zone/timestamp |
| `udf_date19` | timestamp without time zone/timestamp |
| `udf_date20` | timestamp without time zone/timestamp |
| `udf_freeform_01` | character varying/varchar |
| `udf_freeform_02` | character varying/varchar |
| `udf_freeform_03` | character varying/varchar |
| `udf_freeform_04` | character varying/varchar |
| `udf_freeform_05` | character varying/varchar |
| `udf_freeform_06` | character varying/varchar |
| `udf_freeform_07` | character varying/varchar |
| `udf_freeform_08` | character varying/varchar |
| `udf_freeform_09` | character varying/varchar |
| `udf_freeform_10` | character varying/varchar |
| `udf_freeform_11` | character varying/varchar |
| `udf_freeform_12` | character varying/varchar |
| `udf_freeform_13` | character varying/varchar |
| `udf_freeform_14` | character varying/varchar |
| `udf_freeform_15` | character varying/varchar |
| `udf_freeform_16` | character varying/varchar |
| `udf_freeform_17` | character varying/varchar |
| `udf_freeform_18` | character varying/varchar |
| `udf_freeform_19` | character varying/varchar |
| `udf_freeform_20` | character varying/varchar |
| `udf_int01` | integer/int4 |
| `udf_int02` | integer/int4 |
| `udf_int03` | integer/int4 |
| `udf_int04` | integer/int4 |
| `udf_int05` | integer/int4 |
| `udf_int06` | integer/int4 |
| `udf_int07` | integer/int4 |
| `udf_int08` | integer/int4 |
| `udf_int09` | integer/int4 |
| `udf_int10` | integer/int4 |
| `udf_item_priceA` | numeric/numeric |
| `udf_item_priceB` | numeric/numeric |
| `udf_item_priceC` | numeric/numeric |
| `udf_item_priceD` | numeric/numeric |
| `udf_item_priceE` | numeric/numeric |
| `udf_item_priceF` | numeric/numeric |
| `udf_item_priceG` | numeric/numeric |
| `udf_item_priceH` | numeric/numeric |
| `udf_merchgroup01` | character varying/varchar |
| `udf_merchgroup01_id` | integer/int4 |
| `udf_merchgroup02` | character varying/varchar |
| `udf_merchgroup02_id` | integer/int4 |
| `udf_merchgroup03` | character varying/varchar |
| `udf_merchgroup03_id` | integer/int4 |
| `udf_merchgroup04` | character varying/varchar |
| `udf_merchgroup04_id` | integer/int4 |
| `udf_merchgroup05_fk` | character varying/varchar |
| `udf_merchgroup05_fk_id` | integer/int4 |
| `udf_merchgroup06_fk` | character varying/varchar |
| `udf_merchgroup06_fk_id` | integer/int4 |
| `udf_merchgroup07_fk` | character varying/varchar |
| `udf_merchgroup07_fk_id` | integer/int4 |
| `udf_merchgroup08_fk` | character varying/varchar |
| `udf_merchgroup08_fk_id` | integer/int4 |
| `udf_merchgroup09_fk` | character varying/varchar |
| `udf_merchgroup09_fk_id` | integer/int4 |
| `udf_merchgroup10_fk` | character varying/varchar |
| `udf_merchgroup10_fk_id` | integer/int4 |
| `udf_merchgroup11_fk` | character varying/varchar |
| `udf_merchgroup12_fk` | character varying/varchar |
| `udf_merchgroup13_fk` | character varying/varchar |
| `udf_merchgroup14_fk` | character varying/varchar |
| `udf_merchgroup15_fk` | character varying/varchar |
| `udf_merchgroup15_fk_id` | integer/int4 |
| `udf_merchgroup16_fk` | character varying/varchar |
| `udf_merchgroup17_fk` | character varying/varchar |
| `udf_merchgroup18_fk` | character varying/varchar |
| `udf_merchgroup19_fk` | character varying/varchar |
| `udf_merchgroup20_fk` | character varying/varchar |
| `udf_merchgroup21_fk` | character varying/varchar |
| `udf_merchgroup22_fk` | character varying/varchar |
| `udf_merchgroup23_fk` | character varying/varchar |
| `udf_merchgroup24_fk` | character varying/varchar |
| `udf_merchgroup25_fk` | character varying/varchar |
| `udf_num01` | numeric/numeric |
| `udf_num02` | numeric/numeric |
| `udf_num03` | numeric/numeric |
| `udf_num04` | numeric/numeric |
| `udf_num05` | numeric/numeric |
| `udf_num06` | numeric/numeric |
| `udf_num07` | numeric/numeric |
| `udf_num08` | numeric/numeric |
| `udf_num09` | numeric/numeric |
| `udf_num10` | numeric/numeric |
| `udf_yesno01` | character varying/varchar |
| `udf_yesno02` | character varying/varchar |
| `udf_yesno03` | character varying/varchar |
| `udf_yesno04` | character varying/varchar |
| `udf_yesno05` | character varying/varchar |
| `udf_yesno06` | character varying/varchar |
| `udf_yesno07` | character varying/varchar |
| `udf_yesno08` | character varying/varchar |
| `udf_yesno09` | character varying/varchar |
| `udf_yesno10` | character varying/varchar |
| `udf_yesno11` | character varying/varchar |
| `udf_yesno12` | character varying/varchar |
| `udf_yesno13` | character varying/varchar |
| `udf_yesno14` | character varying/varchar |
| `udf_yesno15` | character varying/varchar |
| `udfnum01` | character varying/varchar |
| `uom_code` | character varying/varchar |
| `uom_size_fk` | character varying/varchar |
| `uom_weight_fk` | character varying/varchar |
| `vendor_code_fk` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `company_id` | uuid/uuid |
| `created_at` | timestamp with time zone/timestamptz |
| `description` | text/text |
| `id` | uuid/uuid |
| `item_number` | text/text |
| `licensor_id` | uuid/uuid |
| `merch_group_id` | uuid/uuid |
| `name` | text/text |
| `product_type_id` | uuid/uuid |
| `property_id` | uuid/uuid |
| `raw` | jsonb/jsonb |
| `source_id` | text/text |
| `source_system` | text/text |
| `status` | text/text |
| `style_number` | text/text |
| `updated_at` | timestamp with time zone/timestamptz |

## `designflow.LicenseFeedBacks` → `plm.licensing_feedback`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 8 |
| Target columns | 8 |
| Exact name matches | 1 |
| Fuzzy name matches | 0 |
| Missing in target | 7 |
| Extra on target only | 7 |

### Exact matches

`id`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `access` | character varying/varchar |
| `duplicable` | boolean/bool |
| `explanation` | character varying/varchar |
| `item_order` | integer/int4 |
| `order` | character varying/varchar |
| `phase` | character varying/varchar |
| `status` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `author_name` | text/text |
| `body` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `licensing_status_id` | uuid/uuid |
| `reply_to_id` | uuid/uuid |
| `source_id` | text/text |
| `source_system` | text/text |

## `designflow.licenseList` → `core.licensor`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 9 |
| Target columns | 7 |
| Exact name matches | 0 |
| Fuzzy name matches | 0 |
| Missing in target | 9 |
| Extra on target only | 7 |

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `licenseList_airbyte_emitted_at` | timestamp with time zone/timestamptz |
| `licenseList_airbyte_licenses_hashid` | text/text |
| `licenseList_auditlog` | character varying/varchar |
| `licenseList_code` | character varying/varchar |
| `licenseList_fob_royalty_rate` | double precision/float8 |
| `licenseList_id` | integer/int4 |
| `licenseList_royalty_rate` | double precision/float8 |
| `licenseList_status` | character varying/varchar |
| `licenseList_title` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `code` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `id` | uuid/uuid |
| `metadata` | jsonb/jsonb |
| `name` | text/text |
| `status` | USER-DEFINED/entity_status |
| `updated_at` | timestamp with time zone/timestamptz |

## `designflow.licensingStatus` → `plm.licensing_status`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 14 |
| Target columns | 13 |
| Exact name matches | 2 |
| Fuzzy name matches | 0 |
| Missing in target | 12 |
| Extra on target only | 11 |

### Exact matches

`id`, `status`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `assignee_id` | integer/int4 |
| `assignee_ids` | jsonb/jsonb |
| `assignor_id` | integer/int4 |
| `attachments` | jsonb/jsonb |
| `date` | character varying/varchar |
| `feedback` | character varying/varchar |
| `from` | character varying/varchar |
| `itemheader_id_fk` | integer/int4 |
| `moduser` | character varying/varchar |
| `package` | boolean/bool |
| `pop_comments` | text/text |
| `tagged_group_id` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `completed_at` | timestamp with time zone/timestamptz |
| `created_at` | timestamp with time zone/timestamptz |
| `due_date` | date/date |
| `item_id` | uuid/uuid |
| `licensor_id` | uuid/uuid |
| `metadata` | jsonb/jsonb |
| `milestone` | text/text |
| `property_id` | uuid/uuid |
| `source_id` | text/text |
| `source_system` | text/text |
| `updated_at` | timestamp with time zone/timestamptz |

## `designflow.ProdOrderDetail` → `plm.production_order_line`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 54 |
| Target columns | 14 |
| Exact name matches | 1 |
| Fuzzy name matches | 0 |
| Missing in target | 53 |
| Extra on target only | 13 |

### Exact matches

`id`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `AllocatableWip` | character varying/varchar |
| `BOMFKey` | integer/int4 |
| `CancelledQty` | integer/int4 |
| `colorCode` | character varying/varchar |
| `CompanyCode` | character varying/varchar |
| `ContainerDtlFkey` | integer/int4 |
| `ContainerFkey` | integer/int4 |
| `CostSheetFkey` | integer/int4 |
| `createdTime` | timestamp with time zone/timestamptz |
| `createdUser` | character varying/varchar |
| `CustomerCode` | character varying/varchar |
| `CustPONumber` | character varying/varchar |
| `dimCode` | character varying/varchar |
| `DivisionCode` | character varying/varchar |
| `DueDate` | date/date |
| `EDI943Proc` | character varying/varchar |
| `itemDesc` | character varying/varchar |
| `itemNo` | character varying/varchar |
| `itemPkey` | integer/int4 |
| `labelCode` | character varying/varchar |
| `merchGroup05Desc` | character varying/varchar |
| `modTime` | timestamp without time zone/timestamp |
| `modUser` | character varying/varchar |
| `MovedQty` | integer/int4 |
| `OrigDueDate` | date/date |
| `OrigShipCancelDate` | date/date |
| `OrigShipDate` | date/date |
| `pkey` | integer/int4 |
| `prepackCode` | character varying/varchar |
| `ProdCost` | integer/int4 |
| `ProdLineFkey` | integer/int4 |
| `prodLineSeq` | integer/int4 |
| `ProdOrderCancelType` | character varying/varchar |
| `prodOrderNo` | character varying/varchar |
| `prodQty` | integer/int4 |
| `ProdSeq` | integer/int4 |
| `ReceiveFkey` | integer/int4 |
| `RecvDtlFkey` | integer/int4 |
| `SalesOrderFkey` | integer/int4 |
| `SalesOrderNo` | integer/int4 |
| `ShipCancelDate` | date/date |
| `ShipDate` | date/date |
| `ShipmentFkey` | integer/int4 |
| `sizeCode` | character varying/varchar |
| `SizeExplosionCode` | character varying/varchar |
| `StageCode` | character varying/varchar |
| `StageSeq` | integer/int4 |
| `UDF01` | character varying/varchar |
| `UOMCode` | character varying/varchar |
| `VendorCode` | character varying/varchar |
| `VendorInvoiceFKey` | integer/int4 |
| `WarehouseCode` | character varying/varchar |
| `wipQty` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `created_at` | timestamp with time zone/timestamptz |
| `item_id` | uuid/uuid |
| `line_number` | text/text |
| `metadata` | jsonb/jsonb |
| `production_order_id` | uuid/uuid |
| `quantity_ordered` | numeric/numeric |
| `quantity_shipped` | numeric/numeric |
| `sku` | text/text |
| `source_id` | text/text |
| `source_system` | text/text |
| `status` | text/text |
| `unit_cost` | numeric/numeric |
| `updated_at` | timestamp with time zone/timestamptz |

## `designflow.ProdOrderHeader` → `plm.production_order`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 124 |
| Target columns | 13 |
| Exact name matches | 1 |
| Fuzzy name matches | 0 |
| Missing in target | 123 |
| Extra on target only | 12 |

### Exact matches

`id`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `actual_etd` | character varying/varchar |
| `actual_prod_complete` | character varying/varchar |
| `actual_prod_start` | character varying/varchar |
| `actual_Whse_eta` | character varying/varchar |
| `adjusted_cust_start_date` | character varying/varchar |
| `agentProc` | character varying/varchar |
| `agentProcDate` | character varying/varchar |
| `aPTransactionNo` | character varying/varchar |
| `arrivalPortCode` | character varying/varchar |
| `assembly_start_date` | character varying/varchar |
| `booking_number` | character varying/varchar |
| `buyer_approval_date` | date/date |
| `cal_arrival_date` | character varying/varchar |
| `calculate_fob_delivery` | character varying/varchar |
| `carrierCode` | character varying/varchar |
| `cbm` | character varying/varchar |
| `comment` | character varying/varchar |
| `companyCode` | character varying/varchar |
| `conditions_not_met` | character varying/varchar |
| `container_recvd` | character varying/varchar |
| `containerNo` | character varying/varchar |
| `createdTime` | timestamp with time zone/timestamptz |
| `createdUser` | character varying/varchar |
| `currencyCode` | character varying/varchar |
| `cust_cxl` | character varying/varchar |
| `cust_order_date` | character varying/varchar |
| `cust_start` | character varying/varchar |
| `customerCode` | character varying/varchar |
| `customerPONo` | character varying/varchar |
| `cutterCode` | character varying/varchar |
| `depositAmount` | character varying/varchar |
| `depositBalance` | character varying/varchar |
| `depositDate` | character varying/varchar |
| `depositPaid` | character varying/varchar |
| `depositPosted` | character varying/varchar |
| `discountPerc` | character varying/varchar |
| `dlvy_loc_fk` | integer/int4 |
| `doc_athome` | boolean/bool |
| `doc_bl` | boolean/bool |
| `doc_ctpat` | boolean/bool |
| `doc_fcr` | boolean/bool |
| `doc_inv` | boolean/bool |
| `doc_pl` | boolean/bool |
| `doc_qc` | boolean/bool |
| `doc_tsca` | boolean/bool |
| `dueDate` | character varying/varchar |
| `exchangeRatePkey` | character varying/varchar |
| `factory_committed_prod_start` | character varying/varchar |
| `forwarderProc` | character varying/varchar |
| `forwarderProcDate` | character varying/varchar |
| `freight_forwarder_name` | character varying/varchar |
| `freightForwarderCode` | character varying/varchar |
| `ftySalesRep` | character varying/varchar |
| `hangTagOrderedDate` | character varying/varchar |
| `hangTagReceived` | character varying/varchar |
| `hangTagReceivedDate` | character varying/varchar |
| `hangTagsOrdered` | character varying/varchar |
| `inspection_comment` | character varying/varchar |
| `inspection_result` | character varying/varchar |
| `inspection_start_date` | date/date |
| `item_not_prepro_approved` | character varying/varchar |
| `lcno` | character varying/varchar |
| `mass_prod_start_date` | date/date |
| `massProductionDays` | character varying/varchar |
| `material_arrival_date` | character varying/varchar |
| `mg5` | character varying/varchar |
| `modtime` | timestamp without time zone/timestamp |
| `modUser` | character varying/varchar |
| `num_docs` | character varying/varchar |
| `ok_to_pay_date` | character varying/varchar |
| `origDueDate` | character varying/varchar |
| `origShipCancelDate` | character varying/varchar |
| `origShipDate` | character varying/varchar |
| `packing_start_date` | date/date |
| `paid_date` | character varying/varchar |
| `payTermCode` | character varying/varchar |
| `photo_needed` | boolean/bool |
| `photo_recived` | boolean/bool |
| `postedDate` | character varying/varchar |
| `prepro_approval_date` | character varying/varchar |
| `price_ticket_needed` | boolean/bool |
| `printed` | character varying/varchar |
| `prod_cost` | character varying/varchar |
| `prodCostType` | character varying/varchar |
| `prodCountry` | character varying/varchar |
| `prodOrderDate` | character varying/varchar |
| `prodOrderNo` | character varying/varchar |
| `prodPrinterCode` | character varying/varchar |
| `prodQty` | double precision/float8 |
| `prodReferenceNo` | character varying/varchar |
| `prodRevDate` | character varying/varchar |
| `prodRevNo` | character varying/varchar |
| `prodTypeCode` | character varying/varchar |
| `qc_inspection_date` | character varying/varchar |
| `safety_test_date` | character varying/varchar |
| `safety_test_needed` | boolean/bool |
| `safety_test_passed` | boolean/bool |
| `salesOrderNo` | character varying/varchar |
| `sample_aprov_lead_days` | character varying/varchar |
| `sample_start_date` | character varying/varchar |
| `seasonCode` | character varying/varchar |
| `sent_po_date` | character varying/varchar |
| `sewerCode` | character varying/varchar |
| `shipCancelDate` | character varying/varchar |
| `shipDate` | character varying/varchar |
| `shipPortCode` | character varying/varchar |
| `shipViaCode` | character varying/varchar |
| `svn` | character varying/varchar |
| `ticket_order_date` | character varying/varchar |
| `ticket_tracking_number` | character varying/varchar |
| `tickets_receive_date` | character varying/varchar |
| `uDF01` | character varying/varchar |
| `uDFDate01` | character varying/varchar |
| `uDFDate02` | character varying/varchar |
| `udfnum01` | character varying/varchar |
| `vendor_comment` | character varying/varchar |
| `vendor_start_date` | character varying/varchar |
| `vendorCode` | character varying/varchar |
| `vendorConfirm` | character varying/varchar |
| `vendorConfirmDate` | character varying/varchar |
| `vendorProc` | character varying/varchar |
| `vendorProcDate` | character varying/varchar |
| `warehouseCode` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `actual_ship_date` | date/date |
| `company_id` | uuid/uuid |
| `created_at` | timestamp with time zone/timestamptz |
| `factory_id` | uuid/uuid |
| `metadata` | jsonb/jsonb |
| `order_date` | date/date |
| `production_order_number` | text/text |
| `requested_ship_date` | date/date |
| `source_id` | text/text |
| `source_system` | text/text |
| `status` | text/text |
| `updated_at` | timestamp with time zone/timestamptz |

## `designflow.product_category` → `core.product_category`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 7 |
| Target columns | 6 |
| Exact name matches | 4 |
| Fuzzy name matches | 0 |
| Missing in target | 3 |
| Extra on target only | 2 |

### Exact matches

`created_at`, `id`, `name`, `updated_at`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `created_by` | integer/int4 |
| `is_active` | boolean/bool |
| `updated_by` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `metadata` | jsonb/jsonb |
| `parent_id` | uuid/uuid |

## `designflow.properties_and_characters` → `core.property`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 8 |
| Target columns | 8 |
| Exact name matches | 5 |
| Fuzzy name matches | 0 |
| Missing in target | 3 |
| Extra on target only | 3 |

### Exact matches

`created_at`, `id`, `licensor_id`, `name`, `updated_at`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `source_character_id` | character varying/varchar |
| `source_licensed_property_id` | character varying/varchar |
| `type` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `code` | text/text |
| `metadata` | jsonb/jsonb |
| `status` | USER-DEFINED/entity_status |

## `designflow.property_character_associations` → `core.character`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 5 |
| Target columns | 8 |
| Exact name matches | 3 |
| Fuzzy name matches | 0 |
| Missing in target | 2 |
| Extra on target only | 5 |

### Exact matches

`created_at`, `property_id`, `updated_at`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `character_id` | integer/int4 |
| `licensor_id` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `code` | text/text |
| `id` | uuid/uuid |
| `metadata` | jsonb/jsonb |
| `name` | text/text |
| `status` | USER-DEFINED/entity_status |

## `designflow.RFQGroup` → `plm.rfq_group`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 6 |
| Target columns | 9 |
| Exact name matches | 0 |
| Fuzzy name matches | 0 |
| Missing in target | 6 |
| Extra on target only | 9 |

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `data_added` | timestamp without time zone/timestamp |
| `HasDuplicates` | boolean/bool |
| `IsLegacy` | boolean/bool |
| `RFQGroup_id` | integer/int4 |
| `RFQGroup_name` | character varying/varchar |
| `user_id_fk` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `company_id` | uuid/uuid |
| `created_at` | timestamp with time zone/timestamptz |
| `id` | uuid/uuid |
| `metadata` | jsonb/jsonb |
| `name` | text/text |
| `source_id` | text/text |
| `source_system` | text/text |
| `status` | text/text |
| `updated_at` | timestamp with time zone/timestamptz |

## `designflow.RFQItem` → `plm.rfq_item`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 115 |
| Target columns | 10 |
| Exact name matches | 0 |
| Fuzzy name matches | 0 |
| Missing in target | 115 |
| Extra on target only | 10 |

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `rfq_container_id_fk` | integer/int4 |
| `rfqItem_active` | integer/int4 |
| `rfqItem_adam_fix` | character varying/varchar |
| `rfqItem_agent` | character varying/varchar |
| `rfqItem_archive` | integer/int4 |
| `rfqItem_auditlog` | character varying/varchar |
| `rfqItem_case_pack` | character varying/varchar |
| `rfqItem_cbm_per_piece` | character varying/varchar |
| `rfqItem_cbm_per_price` | character varying/varchar |
| `rfqItem_choosen_vendor` | integer/int4 |
| `rfqItem_comp_retail` | character varying/varchar |
| `rfqItem_container_price` | double precision/float8 |
| `rfqItem_copied_by` | integer/int4 |
| `rfqItem_copied_from_id` | integer/int4 |
| `rfqItem_copied_on` | timestamp with time zone/timestamptz |
| `rfqItem_created_date` | timestamp with time zone/timestamptz |
| `rfqItem_customer` | integer/int4 |
| `rfqItem_date_modified` | timestamp without time zone/timestamp |
| `rfqItem_default_cbm` | character varying/varchar |
| `rfqItem_delivery_loc` | integer/int4 |
| `rfqItem_depth` | integer/int4 |
| `rfqItem_description` | character varying/varchar |
| `rfqItem_dilution` | character varying/varchar |
| `rfqItem_divCode_id_fk` | character varying/varchar |
| `rfqItem_duty_rate` | character varying/varchar |
| `rfqItem_duty_rate_dollar_amount` | character varying/varchar |
| `rfqItem_duty_rate_equation` | character varying/varchar |
| `rfqItem_factories_step_at` | timestamp without time zone/timestamp |
| `rfqItem_fob_cost` | character varying/varchar |
| `rfqItem_freight` | character varying/varchar |
| `rfqItem_gen_fob_entered_margin` | double precision/float8 |
| `rfqItem_gen_fob_entered_sell_price` | double precision/float8 |
| `rfqItem_gen_fob_margin` | character varying/varchar |
| `rfqItem_gen_fob_netsell` | character varying/varchar |
| `rfqItem_gen_fob_pricesale` | character varying/varchar |
| `rfqItem_gen_fob_royalty` | character varying/varchar |
| `rfqItem_gen_fob_sellprice` | character varying/varchar |
| `rfqItem_gen_ldp_margin` | character varying/varchar |
| `rfqItem_gen_mddp_entered_margin` | double precision/float8 |
| `rfqItem_gen_mddp_entered_sell_price` | double precision/float8 |
| `rfqItem_gen_mddp_margin` | character varying/varchar |
| `rfqItem_gen_mddp_netsell` | character varying/varchar |
| `rfqItem_gen_mddp_pricesale` | character varying/varchar |
| `rfqItem_gen_mddp_royalty` | character varying/varchar |
| `rfqItem_gen_mddp_sellprice` | character varying/varchar |
| `rfqItem_gen_poe_entered_margin` | double precision/float8 |
| `rfqItem_gen_poe_entered_sell_price` | double precision/float8 |
| `rfqItem_gen_poe_margin` | character varying/varchar |
| `rfqItem_gen_poe_netsell` | character varying/varchar |
| `rfqItem_gen_poe_pricesale` | character varying/varchar |
| `rfqItem_gen_poe_royalty` | character varying/varchar |
| `rfqItem_gen_poe_sellprice` | character varying/varchar |
| `rfqItem_gen_whse_entered_margin` | double precision/float8 |
| `rfqItem_gen_whse_entered_sell_price` | double precision/float8 |
| `rfqItem_gen_whse_margin` | character varying/varchar |
| `rfqItem_gen_whse_netsell` | character varying/varchar |
| `rfqItem_gen_whse_pricesale` | character varying/varchar |
| `rfqItem_gen_whse_royalty` | character varying/varchar |
| `rfqItem_gen_whse_sellprice` | character varying/varchar |
| `rfqItem_id` | integer/int4 |
| `rfqItem_is_landed_cost_manual` | boolean/bool |
| `rfqItem_landed_cost` | character varying/varchar |
| `rfqItem_lic_fob_entered_margin` | double precision/float8 |
| `rfqItem_lic_fob_entered_sell_price` | double precision/float8 |
| `rfqItem_lic_fob_margin` | character varying/varchar |
| `rfqItem_lic_fob_netsell` | character varying/varchar |
| `rfqItem_lic_fob_pricesale` | character varying/varchar |
| `rfqItem_lic_fob_royalty` | character varying/varchar |
| `rfqItem_lic_fob_sellprice` | character varying/varchar |
| `rfqItem_lic_mddp_entered_margin` | double precision/float8 |
| `rfqItem_lic_mddp_entered_sell_price` | double precision/float8 |
| `rfqItem_lic_mddp_margin` | character varying/varchar |
| `rfqItem_lic_mddp_netsell` | character varying/varchar |
| `rfqItem_lic_mddp_pricesale` | character varying/varchar |
| `rfqItem_lic_mddp_royalty` | character varying/varchar |
| `rfqItem_lic_mddp_sellprice` | character varying/varchar |
| `rfqItem_lic_poe_entered_margin` | double precision/float8 |
| `rfqItem_lic_poe_entered_sell_price` | double precision/float8 |
| `rfqItem_lic_poe_margin` | character varying/varchar |
| `rfqItem_lic_poe_netsell` | character varying/varchar |
| `rfqItem_lic_poe_pricesale` | character varying/varchar |
| `rfqItem_lic_poe_royalty` | character varying/varchar |
| `rfqItem_lic_poe_sellprice` | character varying/varchar |
| `rfqItem_lic_whse_entered_margin` | double precision/float8 |
| `rfqItem_lic_whse_entered_sell_price` | double precision/float8 |
| `rfqItem_lic_whse_margin` | character varying/varchar |
| `rfqItem_lic_whse_netsell` | character varying/varchar |
| `rfqItem_lic_whse_pricesale` | character varying/varchar |
| `rfqItem_lic_whse_royalty` | character varying/varchar |
| `rfqItem_lic_whse_sellprice` | character varying/varchar |
| `rfqItem_license` | character varying/varchar |
| `rfqItem_logistic_load` | character varying/varchar |
| `rfqItem_notes` | character varying/varchar |
| `rfqItem_picture` | character varying/varchar |
| `rfqItem_picturethumb` | character varying/varchar |
| `rfqItem_price_per_cbm` | character varying/varchar |
| `rfqItem_price_sales_snapshots` | text/text |
| `rfqItem_quantity` | character varying/varchar |
| `rfqItem_quote_update` | character varying/varchar |
| `rfqItem_requested_price_cells` | text/text |
| `rfqItem_rfq_group` | integer/int4 |
| `rfqItem_royalty` | double precision/float8 |
| `rfqItem_size_l_w` | integer/int4 |
| `rfqItem_source_item_id` | integer/int4 |
| `rfqItem_source_item_num` | character varying/varchar |
| `rfqItem_standardized_products` | character varying/varchar |
| `rfqItem_step` | integer/int4 |
| `rfqItem_style_number` | character varying/varchar |
| `rfqItem_tech_pack_link` | character varying/varchar |
| `rfqItem_udf1` | integer/int4 |
| `rfqItem_udf2` | integer/int4 |
| `rfqItem_udf3` | integer/int4 |
| `rfqItem_udf4` | integer/int4 |
| `rfqItem_warehouse` | character varying/varchar |
| `rfqItem_wholesale` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `created_at` | timestamp with time zone/timestamptz |
| `id` | uuid/uuid |
| `item_id` | uuid/uuid |
| `metadata` | jsonb/jsonb |
| `rfq_group_id` | uuid/uuid |
| `source_id` | text/text |
| `source_system` | text/text |
| `status` | text/text |
| `target_cost` | numeric/numeric |
| `updated_at` | timestamp with time zone/timestamptz |

## `designflow.RFQVendor` → `plm.rfq_vendor`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 26 |
| Target columns | 9 |
| Exact name matches | 0 |
| Fuzzy name matches | 0 |
| Missing in target | 26 |
| Extra on target only | 9 |

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `carton_height` | double precision/float8 |
| `carton_length` | double precision/float8 |
| `carton_width` | double precision/float8 |
| `fob_country` | character varying/varchar |
| `fob_port` | character varying/varchar |
| `lead_time` | integer/int4 |
| `price_terms` | character varying/varchar |
| `quote_date` | date/date |
| `req_status` | integer/int4 |
| `requote_requested` | boolean/bool |
| `RFQitem_id_fk` | integer/int4 |
| `RFQVendor_amount` | character varying/varchar |
| `RFQVendor_archive_optout` | boolean/bool |
| `RFQVendor_archived` | boolean/bool |
| `RFQVendor_cbm_pc` | character varying/varchar |
| `RFQVendor_id` | integer/int4 |
| `RFQVendor_note` | character varying/varchar |
| `RFQVendor_status` | character varying/varchar |
| `RFQVendor_suggested_amount` | character varying/varchar |
| `RFQVendor_suggested_cbm_pc` | character varying/varchar |
| `RFQVendor_suggested_note` | character varying/varchar |
| `std_vendor_id_fk` | character varying/varchar |
| `suggested_carton_height` | double precision/float8 |
| `suggested_carton_length` | double precision/float8 |
| `suggested_carton_width` | double precision/float8 |
| `vendor_id_fk` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `created_at` | timestamp with time zone/timestamptz |
| `factory_id` | uuid/uuid |
| `id` | uuid/uuid |
| `metadata` | jsonb/jsonb |
| `rfq_group_id` | uuid/uuid |
| `source_id` | text/text |
| `source_system` | text/text |
| `status` | text/text |
| `updated_at` | timestamp with time zone/timestamptz |

## `designflow.Roles` → `app.role`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 2 |
| Target columns | 6 |
| Exact name matches | 2 |
| Fuzzy name matches | 0 |
| Missing in target | 0 |
| Extra on target only | 4 |

### Exact matches

`Id`, `Name`

### Missing in target

_None — every DesignFlow column has an exact or fuzzy counterpart._

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `created_at` | timestamp with time zone/timestamptz |
| `description` | text/text |
| `slug` | USER-DEFINED/app_role |
| `updated_at` | timestamp with time zone/timestamptz |

## `designflow.user_notification` → `app.notification`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 8 |
| Target columns | 11 |
| Exact name matches | 2 |
| Fuzzy name matches | 0 |
| Missing in target | 6 |
| Extra on target only | 9 |

### Exact matches

`id`, `title`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `created_date` | date/date |
| `event` | character varying/varchar |
| `message` | character varying/varchar |
| `type` | character varying/varchar |
| `unread` | boolean/bool |
| `user_id_fk` | integer/int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `app` | USER-DEFINED/app_name |
| `body` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `payload` | jsonb/jsonb |
| `profile_id` | uuid/uuid |
| `read_at` | timestamp with time zone/timestamptz |
| `target_id` | uuid/uuid |
| `target_schema` | text/text |
| `target_table` | text/text |

## `designflow.users` → `app.profile`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 21 |
| Target columns | 11 |
| Exact name matches | 3 |
| Fuzzy name matches | 0 |
| Missing in target | 18 |
| Extra on target only | 8 |

### Exact matches

`email`, `id`, `status`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `_airbyte_emitted_at` | timestamp with time zone/timestamptz |
| `_airbyte_users_hashid` | text/text |
| `adddate` | character varying/varchar |
| `auditlog` | character varying/varchar |
| `expire` | character varying/varchar |
| `graph_photo` | text/text |
| `graph_photo_synced_at` | timestamp with time zone/timestamptz |
| `lastname` | character varying/varchar |
| `level` | character varying/varchar |
| `name` | character varying/varchar |
| `notes` | character varying/varchar |
| `notificationemail` | character varying/varchar |
| `notificationsms` | character varying/varchar |
| `passw` | character varying/varchar |
| `phonenum` | character varying/varchar |
| `profile_photo` | text/text |
| `subleveladmin` | character varying/varchar |
| `subscription` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `auth_user_id` | uuid/uuid |
| `avatar_url` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `display_name` | text/text |
| `external_identifier` | text/text |
| `provider` | text/text |
| `source_refs` | jsonb/jsonb |
| `updated_at` | timestamp with time zone/timestamptz |

## `designflow.vendor` → `core.factory`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 17 |
| Target columns | 10 |
| Exact name matches | 0 |
| Fuzzy name matches | 0 |
| Missing in target | 17 |
| Extra on target only | 10 |

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `factory_id_fk` | integer/int4 |
| `vendor_access` | character varying/varchar |
| `vendor_address1` | character varying/varchar |
| `vendor_address2` | character varying/varchar |
| `vendor_company_name` | character varying/varchar |
| `vendor_company_nickname` | character varying/varchar |
| `vendor_country` | character varying/varchar |
| `vendor_email` | character varying/varchar |
| `vendor_id` | integer/int4 |
| `vendor_lastname` | character varying/varchar |
| `vendor_name` | character varying/varchar |
| `vendor_passw` | character varying/varchar |
| `vendor_phone1` | character varying/varchar |
| `vendor_phone2` | character varying/varchar |
| `vendor_profile_photo` | text/text |
| `vendor_status` | character varying/varchar |
| `vendor_wechatId` | character varying/varchar |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `code` | text/text |
| `company_id` | uuid/uuid |
| `country` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `id` | uuid/uuid |
| `metadata` | jsonb/jsonb |
| `name` | text/text |
| `status` | USER-DEFINED/entity_status |
| `updated_at` | timestamp with time zone/timestamptz |
| `vendor_group` | text/text |

## `designflow.vendorGroup` → `core.factory`

_

| Metric | Count |
|---|---:|
| DesignFlow columns | 3 |
| Target columns | 10 |
| Exact name matches | 2 |
| Fuzzy name matches | 0 |
| Missing in target | 1 |
| Extra on target only | 8 |

### Exact matches

`id`, `name`

### Missing in target (need mapping or new columns)

| DesignFlow column | Type |
|---|---|
| `factory_ids` | ARRAY/_int4 |

### Extra on target only (canonical fields)

| Target column | Type |
|---|---|
| `code` | text/text |
| `company_id` | uuid/uuid |
| `country` | text/text |
| `created_at` | timestamp with time zone/timestamptz |
| `metadata` | jsonb/jsonb |
| `status` | USER-DEFINED/entity_status |
| `updated_at` | timestamp with time zone/timestamptz |
| `vendor_group` | text/text |
