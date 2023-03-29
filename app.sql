FUNCTION GET_TRIP_LEG_VR (p_line_id        IN NUMBER,     -- order line id
                              p_contract_num   IN VARCHAR2)
        RETURN NUMBER
    IS
        --declare
        TYPE cost_log IS RECORD
        (
            org_id             NUMBER,
            order_line_id      NUMBER,
            --    order_line         NUMBER,
            cost_type          VARCHAR2 (200),
            cost_amount        NUMBER,
            cost_unit_price    NUMBER,
            cost_qty           NUMBER,
            cost_uom           VARCHAR2 (10),
            cost_date          DATE,
            cost_att1          VARCHAR2 (200),
            cost_att2          VARCHAR2 (200)
        );

        l_cost_log                 cost_log;
        l_contract_number          VARCHAR2 (100) := 'JetCardContract01'; --JZcontract02';
        l_date                     DATE := SYSDATE ();
        l_fc                       NUMBER := 0;
        l_nfc                      NUMBER := 0;
        l_fca                      NUMBER := 0;
        l_int_ratio                NUMBER := 0;
        l_bill_hour_rate           NUMBER;
        l_billing_hours            NUMBER;
        l_billing_subtotal         NUMBER;
        l_fees                     NUMBER;
        l_leg_total                NUMBER;
        l_leg_line_number          NUMBER;

        l_NFC_item_number          VARCHAR2 (80);
        l_FC_item_number           VARCHAR2 (80);
        l_FCA_item_number          VARCHAR2 (80);
        l_term_item_number         VARCHAR2 (60);
        l_fca_waiver_flag          VARCHAR2 (3);
        l_peak_time_flag           VARCHAR2 (200);

        l_item_number              VARCHAR2 (200);
        l_leg_vr_link_id           VARCHAR2 (10);
        l_apply_slw_flag           VARCHAR2 (5);
        l_order_number_line_no     VARCHAR2 (200);
        l_actual_prog              VARCHAR2 (100);
        l_psa_flag                 VARCHAR2 (3);
        l_order_type               VARCHAR2 (100);
        l_currency_code            VARCHAR2 (100);

        l_hourly_rate_item         VARCHAR2 (100);
        l_hourly_rate              NUMBER := 0;
        L_owner_prog               VARCHAR2 (100);
        l_pref_std                 VARCHAR2 (100);
        l_psa_stat                 VARCHAR2 (3) := 'S';
        l_fca_waiver_rule          VARCHAR2 (100);
        l_billing_prog             VARCHAR2 (100);
        l_leg_date                 DATE;
        l_term_rules               VARCHAR2 (10);
        l_ratio_string             VARCHAR2 (100);
        l_fca_ratio_override       NUMBER := 0;
        l_fca_override             NUMBER := 0;
        l_G650_PSA_hours           NUMBER := 0;
        l_rate_rule                VARCHAR2 (10);


        --

        --      l_contract_type                VARCHAR2 (100);

        CURSOR c_order_line IS   -- get all order line and header info needed.
            SELECT *
              FROM XXOKS_trip_ord_v
             WHERE leg_line_id = p_line_id;

        CURSOR c_FCA_waiver_flag IS -- get all order line and header info needed.
            SELECT *
              FROM XXOKS_CONTRACT_TERM_V
             WHERE     contract_number = l_contract_number
                   AND item_number = 'UK_FCA_WAIVER';

        CURSOR c_revenue_item_number IS -- use this to get nfc/fc revenue item number
            SELECT *
              FROM xxoks_revenue_item_map_v map
             WHERE contract_term_item = l_hourly_rate_item;

        --'UK_JC_PREM_HRATE_P600';

        l_requested_prog_revenue   VARCHAR2 (100);
        l_omb_status               VARCHAR2 (20) := 'Draft';
        l_ct_fca_ov_ratio          NUMBER;
        l_bill_rate                NUMBER;
        l_l_date                   DATE; -- used to get hourly rate for pre-travel trip
        l_c_start_date             DATE;                -- contract start_date
        l_use_tier_pricing         NUMBER;

        l_tier_price               NUMBER;
        l_plist_name               VARCHAR2 (100);
        l_tier_name                VARCHAR2 (100);
        l_pp                       VARCHAR2 (10);
        l_total_fly_hours          NUMBER;
        l_average_fly_hours        NUMBER;
        l_total_flight_hours       NUMBER;
        l_number_of_legs           NUMBER := 1;
        l_ratio_override_note      VARCHAR2 (100);
        l_psa_override_note        VARCHAR2 (100);
        l_other_override_note      VARCHAR2 (100);
        l_remarks                  VARCHAR2 (250);



        l_l_fc                     NUMBER;
        l_l_nfc                    NUMBER;            --           OUT NUMBER,
        l_l_fca                    NUMBER;       --, --            OUT NUMBER,
        l_l_hourly_rate            NUMBER;          --, --         OUT NUMBER,
        l_l_hourly_rate_item       VARCHAR2 (100);           --  OUT VARCHAR2,
        l_l_status                 VARCHAR2 (200);

        CURSOR c_get_trip_pp (l_order_number VARCHAR2)
        IS
            SELECT attribute15             pp,
                   NVL (attribute2, 0)     total_flight_hours,
                   NVL (attribute5, 0)     total_fly_hours
              FROM oe_order_headers
             WHERE order_number = l_order_number;
    BEGIN
        -- RETURN 10000;



        DBMS_OUTPUT.put_line ('---- VR START OF LEG_VR DEBUG');

        --
        --0. LOOP from FO_TRIP_ORD_V for each leg to get all leg info
        l_cost_log.order_line_id := p_line_id;
        DBMS_OUTPUT.put_line ('---- VR 1. line number:' || p_line_id);

        FOR c IN c_order_line
        LOOP
            DBMS_OUTPUT.put_line (
                   '----VR_2. get into loop: '
                || l_order_type
                || ' , AC:'
                || c.requested_prog
                || '/'
                || c.actual_prog
                || '/oac:'
                || c.owner_prog
                || ' ,leg_t_date:'
                || c.leg_t_date);
            l_order_type := c.order_type;
            l_currency_code := c.currency_code;

            -- in future, can add trip type on this list
            IF SUBSTR (l_order_type, 1, 7) IN ('UK_TRIP', 'MT_TRIP') --EZ 1012 added malta order type             --
            THEN
                --1. get line info and derive contract number
                l_contract_number := c.ohcontract_number;
                l_item_number := c.item_number;
                l_leg_vr_link_id := c.leg_vr_link_id;
                l_order_number_line_no :=
                    c.order_number || '-' || c.line_number;


                -- conditions to handle jetcard request vs actul downgrade.
                l_actual_prog :=
                    CASE
                        WHEN NVL (c.requested_prog, c.actual_prog) LIKE
                                 ('%L450')
                        THEN
                            c.actual_prog
                        ELSE
                            NVL (c.requested_prog, c.actual_prog)
                    END;        --ez 1017 if no request_prog, use actual prog.
                -- ez 1018 handle US L450
                L_owner_prog := c.Owner_Prog;
                l_date := c.ordered_date; -- changed to header.  to make it consistant.  not use leg level.
                -- leg_t_date; --c.utc_land_time;         -- can be utc_take_off_time
                l_leg_date := c.leg_t_date; -- use this for waiver, and peack day etc.



                SELECT DISTINCT start_date
                  INTO l_c_start_date
                  FROM xxoks_contract_header_v
                 WHERE contract_number = l_contract_number;

                l_l_date := GREATEST (l_leg_date, l_c_start_date);
                -- use l_l_date to get values.
                -- 3. get the fc/nfc items --
                -- a. fractional should decide based on PSA/SSA.
                -- b. jetcard, use peak day flag
                --=====================================================================
                -- new logic was defined
                -- 0410 -- any new contract after 80703 will use new logic
                --0511 REMOVED old logic.

                --l_fc := 563;                                -- set default

                DBMS_OUTPUT.put_line (
                       '---- VR_3. l_date=ord_date:'
                    || l_date
                    || ', Leg_date=l_l_date:'
                    || l_l_date);


                l_requested_prog_revenue :=
                    CASE
                        WHEN REPLACE (NVL (c.requested_prog, c.actual_prog),
                                      'US ',
                                      '') LIKE
                                 ('%L450')
                        THEN
                            c.actual_prog
                        ELSE
                            REPLACE (NVL (c.requested_prog, c.actual_prog),
                                     'US ',
                                     '')
                    END;
                --1018 to convert US l450 TO L500 for revenue items                         -- get revenue prog

                DBMS_OUTPUT.put_line (
                       '---- 3.1 update ACTUAL US l450 for revenue AC: '
                    || l_requested_prog_revenue);

                ----------------------------------------
                --======================================
                --STEP 1.  ONLY PROCESS UK_TRIP_LEG_VR item  -- this item is used for both UK and Malta

                IF l_item_number = 'UK_TRIP_LEG_VR'
                THEN
                    --1. GET FCA waiver-- may add some conditions e.g. 2 month etc.
                    --0620, use the new function to get waiver flag.
                    -- this can return 0
                    l_fca_waiver_flag :=
                        get_FCA_WAVER_flag (l_contract_number, '', SYSDATE --l_leg_date
                                                                          );

                    DBMS_OUTPUT.put_line (
                           '------ VR_4.1 fca waiver FLAG:'
                        || l_contract_number
                        || ':'
                        || l_fca_waiver_flag);

                    -- 2. get peak_time_flag (come from camp to oracle migration
                    --l_peak_time_flag := c.peak_time_flag;
                    IF c.PEAK_TIME_FLAG IS NOT NULL
                    THEN
                        l_peak_time_flag := c.PEAK_TIME_FLAG;
                    ELSE
                        l_peak_time_flag :=
                            peak_day_flag (l_actual_prog, l_leg_date); --l_date);
                    END IF;

                    DBMS_OUTPUT.put_line (
                        '------ VR_4.2 Peak time flag:' || l_peak_time_flag);

                    -- validate trip basic info
                    -- a. contract number
                    -- b. from/to
                    -- c. aircraft type, and upgrade/downgrade
                    -- d. get FC, NFC, FCA



                    --2. calculate leg's trip hourly cost and * billing hours
                    --   contract terms are pulled from contract
                    --   trip hours will be pulled from trip transactions.

                    l_date := NVL (c.leg_t_date, SYSDATE); -- using land date as the date
                    l_term_item_number := c.leg_line_number || 'TERM';

                    -- 3. get the fc/nfc items --
                    -- a. fractional should decide based on PSA/SSA.
                    -- b. jetcard, use peak day flag
                    --=====================================================================
                    -- new logic was defined
                    -- 0410 -- any new contract after 80703 will use new logic
                    --0511 REMOVED old logic.

                    --l_fc := 563;                                -- set default


                    l_fc :=
                        NVL (xxoks_pricing_pkg.GET_FC (l_contract_number,
                                                       l_actual_prog, --L_owner_prog, --'P600', ez 1017 use request/actual
                                                       l_currency_code,
                                                       SYSDATE),
                             0);

                    --     only have EUR FC global value

                    DBMS_OUTPUT.put_line (
                        '------ VR_4.4 fc/sysdate ' || l_fc || '/' || SYSDATE);

                    -- get fca_override from leg:  amount
                    l_fca_override := c.fca_ratio_override;

                    -----------------------------------------------------------------------------------------------------------------------
                    --jcard
                    ------------
                    --jetcard -- new logic, use dervied item
                    ------------
                    IF    c.contract_type = 'JetCard'
                       OR c.contract_type = 'Trial Programme'
                    THEN
                        DBMS_OUTPUT.put_line (
                            '------ VR_5. INTO JT loop' || SYSDATE);

                        l_fc :=
                            NVL (xxoks_pricing_pkg.GET_FC (l_contract_number,
                                                           l_actual_prog, --L_owner_prog, --'P600', ez 1017 use request/actual
                                                           l_currency_code,
                                                           SYSDATE),
                                 0);       -- ez 1115 jetcard use actual prog.

                        IF l_fca_waiver_flag <= 0
                        THEN
                            L_FCA :=
                                get_fca (p_line_id,
                                         l_contract_number,
                                         l_actual_prog,
                                         l_leg_date,                 --l_date,
                                         l_currency_code);
                        ELSE
                            L_FCA := 0;
                        END IF;

                        -- get fca amount

                        DBMS_OUTPUT.put_line (
                               '-------- 5.1 J1.1 fca: '
                            || L_FCA
                            || 'flag:'
                            || l_fca_waiver_flag);

                        IF l_peak_time_flag = 'N'
                        THEN
                            l_pref_std := 'STD';
                        ELSE
                            l_pref_std := 'PREM';
                        END IF;

                        --jetccard fca item do not need to derive from revenue mapping table
                        IF c.contract_type = 'JetCard'
                        THEN
                            l_FCA_item_number :=
                                   'UK_FCA_JC_'
                                || REPLACE (l_requested_prog_revenue,
                                            'US ',
                                            '');              --l_actual_prog;
                        ELSE
                            l_FCA_item_number :=
                                   'UK_FCA_TRIAL_'
                                || REPLACE (l_requested_prog_revenue,
                                            'US ',
                                            '');              --l_actual_prog;
                        END IF;

                        DBMS_OUTPUT.put_line (
                               '-------- 5.2 JFCA NUMBER : '
                            || l_FCA_item_number);

                        --1. get contract hourly rate item number from mapping
                        --use sub_stard_date and time
                        --0626
                        l_other_override_note :=
                               l_other_override_note
                            || ' ;FCAW:'
                            || l_fca_waiver_flag;

                        BEGIN
                            SELECT RATE.sub_line_item, RATE.hourly_rate
                              INTO l_hourly_rate_item, l_hourly_rate
                              FROM XXOKS_HOURLY_RATE_V       rate,
                                   xxoks_revenue_item_map_v  map
                             WHERE     1 = 1
                                   AND RATE.SUB_LINE_ITEM =
                                       map.CONTRACT_TERM_ITEM
                                   AND rate.contract_number =
                                       l_contract_number             --'80705'
                                   AND pref_std = l_pref_std --'STD' peck time
                                   AND ac =
                                       CASE
                                           WHEN l_actual_prog NOT IN
                                                    ('P600', 'L500')
                                           THEN
                                               'P600'
                                           ELSE
                                               l_actual_prog
                                       END
                                   --'P600' --actual prog-- jetcard can use other ac to fly, but the hourly rate has to get from p600/l500.
                                   AND TYPE = 'JCARD' --FRAX'  -- CAN BE JCARD/FRAX
                                   AND fc_nfc_fca = 'NFC' -- CAN BE NFC/FC -- ONLY USE FC to get single line
                                   AND l_l_date >= RATE.sub_START_DATE --ez 0109 to pick hourly rate for pre contract trips
                                   AND l_l_date <= RATE.sub_END_DATE + 0.9999 -- add to .
                                                                             ;

                            IF l_actual_prog NOT IN ('P600', 'L500') -- EZ 1115, adjust revenue string for JETCARD.
                            THEN
                                l_hourly_rate_item :=
                                    REPLACE (
                                        l_hourly_rate_item,
                                        'P600',
                                        REPLACE (l_actual_prog, 'US ', ''));
                            END IF;
                        -- can change to l_leg_date if needed.
                        EXCEPTION
                            WHEN OTHERS
                            THEN
                                NULL;
                        END;

                        p_get_con_hourly_rate (l_contract_number,
                                               'JCARD', --p_rate_type               , -- frax/jc
                                               l_l_date, --                   DATE,
                                               l_actual_prog, --               VARCHAR2, -- used to match AC
                                               c.UTC_FLY_TIME_SET, -- get string p_leg_rate_o               VARCHAR2, -- override string
                                               l_pref_std, --               VARCHAR2, -- std/other
                                               l_l_fc, --           OUT NUMBER,
                                               l_l_nfc, --           OUT NUMBER,
                                               l_l_fca, --            OUT NUMBER,
                                               l_l_hourly_rate, --         OUT NUMBER,
                                               l_l_hourly_rate_item, --  OUT VARCHAR2,
                                               l_l_status);  -- OUT VARCHAR2);

                        IF l_l_status = 'LEG-OV-OK'
                        THEN
                            l_fc := l_l_fc;
                            l_nfc := l_l_nfc;
                            l_fca := l_l_fca;
                            l_hourly_rate := l_l_fc + l_l_nfc;
                        END IF;

                        l_other_override_note :=
                            l_other_override_note || l_l_status;

                        DBMS_OUTPUT.put_line (
                               '-------- 5.3.2 OVERRIDE STATUS: l_l_error:'
                            || l_l_status
                            || ':'
                            || l_hourly_rate
                            || ' , l_l_fc/nfc/fca:'
                            || l_l_fc
                            || '/'
                            || l_l_nfc
                            || '/'
                            || l_l_fca
                            || ' , l_actual_prog:'
                            || l_actual_prog);


                        DBMS_OUTPUT.put_line (
                               '-------- 5.3 j HOURLY RATE:'
                            || l_hourly_rate_item
                            || ':'
                            || l_hourly_rate
                            || ', JC_l_date'
                            || l_date
                            || ', Requested AC (revenue):'
                            || l_requested_prog_revenue);

                        ----------------------
                        -- assign revenue item
                        ----------------------
                        --0720  -- use l_requested_prog_revenue to get revenue item
                        FOR r IN c_revenue_item_number
                        LOOP
                            CASE
                                WHEN     r.fc_nfc_fca = 'NFC'
                                     AND r.ac =
                                         REPLACE (l_requested_prog_revenue,
                                                  'US ',
                                                  '') --l_requested_prog_revenue --l_actual_prog   --l_owner_prog
                                THEN
                                    l_NFC_item_number := r.revenue_item;

                                    DBMS_OUTPUT.put_line (
                                           '-------- 5.3.1  J. revenue item NFC:'
                                        || l_NFC_item_number);
                                WHEN     r.fc_nfc_fca = 'FC'
                                     AND r.ac =
                                         REPLACE (l_requested_prog_revenue,
                                                  'US ',
                                                  '') --l_requested_prog_revenue --l_actual_prog   --l_owner_prog
                                THEN
                                    l_FC_item_number := r.revenue_item;
                                    DBMS_OUTPUT.put_line (
                                           '-------- 5.3.2  J. revenue item FC:'
                                        || l_FC_item_number);
                                ELSE
                                    NULL;
                            END CASE;

                            DBMS_OUTPUT.put_line (
                                   '-------- 5.4  J. revenue item NFC:'
                                || l_NFC_item_number
                                || ' FC:'
                                || l_FC_item_number);
                        END LOOP;

                        IF c.contract_type <> 'JetCard' -- need to get TRIAL REVENUE ITEM
                        --ez 2023 0104
                        THEN
                            l_NFC_item_number :=
                                REPLACE (l_NFC_item_number, 'JC', 'TRIAL');
                            l_FC_item_number :=
                                REPLACE (l_FC_item_number, 'JC', 'TRIAL');
                        END IF;



                        DBMS_OUTPUT.put_line (
                               '-------- 5.5 ADJ revenue item NFC:'
                            || l_NFC_item_number
                            || ' FC:'
                            || l_FC_item_number);

                        -- add US AC rate override logic:

                        IF     SUBSTR (c.requested_prog, 1, 2) = 'US'
                           AND l_l_status <> 'OVERIDE SUCCESSFULLY' -- if leg level rate override, ignore US override
                        THEN
                            l_fca := 0;
                            l_hourly_rate :=
                                get_us_ac_rate (c.requested_prog, --REPLACE (c.requested_prog, 'US ', ''),
                                                                  l_leg_date);
                            l_other_override_note :=
                                l_other_override_note || 'US-0';
                        END IF;



                        DBMS_OUTPUT.put_line (
                               '-------- 5.6  flat fee revenue item NFC:'
                            || l_NFC_item_number
                            || ' FC:'
                            || l_FC_item_number
                            || ', Flat JC US l_hourly_rate:'
                            || l_hourly_rate
                            || ' done JC LOGIC ...............................');
                    ELSE
                        ----------------------------------------------------------------------------------------------------------------------------
                        --frax
                        -----------
                        --FRAX+Access 2.0,+Access 1.0 (this one use two HRs but use anniversary.
                        ------------
                        DBMS_OUTPUT.put_line (
                            '------------------------------------------');
                        DBMS_OUTPUT.put_line (
                            '---------6.0 ------Frax start: ');

                        l_fc :=
                            NVL (xxoks_pricing_pkg.GET_FC (l_contract_number,
                                                           L_owner_prog, --'P600', ez 1017 use request/actual
                                                           l_currency_code,
                                                           SYSDATE),
                                 0);

                        DBMS_OUTPUT.put_line (
                               '-------- 6.1  frax Owner Prog:'
                            || l_owner_prog
                            || ' FC:'
                            || l_fc
                            || ', date (should use l_l_date?:'
                            || SYSDATE);
                        ------------------
                        -- ez 0125 add G650 tier pricing:
                        l_use_tier_pricing :=
                            GET_TERM_VALUE ('Use Tier Pricing', -- order line id
                                            l_contract_number,
                                            l_date);
                        DBMS_OUTPUT.put_line (
                               '-------- 6.1.1 check tier pricing:'
                            || l_use_tier_pricing);

                        ----------------------------------------------------------------------------------
                        --tier pricing
                        --============================================
                        IF     l_use_tier_pricing = 1                       --
                           AND c.owner_prog = 'G650'
                           AND c.requested_prog = 'G650'
                           AND c.actual_prog = 'G650'
                        THEN
                            l_plist_name :=
                                'UK CONTRACT Tier Primary Price List USD';
                            -- can derive with currency etc.
                            l_tier_name := 'Global Tier';

                            --assign revenue items for G650
                            --get tier pricing:
                            IF NVL (c.apply_SLW_flag, 'N') = 'Y' --AND c.leg_fly_hours < 0.8  ---
                            THEN
                                l_billing_hours := c.leg_fly_hours + 0.2; --c.leg_incremental_hours;
                                l_other_override_note :=
                                    l_other_override_note || ' ;SLW:Y'; --ez add other notes to remarks
                            ELSE
                                l_billing_hours :=
                                    GREATEST (c.leg_billing_hours, 1);
                            -- a ssume migration from camp has done all billing hours calculation.
                            -- if a short leg waiver is applied, this will show the billing hours.


                            END IF;


                            l_hourly_rate :=
                                get_tier_price (l_contract_number,
                                                l_plist_name,
                                                l_tier_name,
                                                c.leg_billing_hours,
                                                l_date);

                            DBMS_OUTPUT.put_line (
                                   '-------- 6.1.2 get tier hourly rate: '
                                || l_hourly_rate);

                            l_NFC_item_number := 'UK_NFC_STD_G650';

                            l_FC_item_number := 'UK_FC_STD_G650';
                            l_fca_item_number := 'UK_FCA_G650';

                            --FCA revenue item will not be derived from revenue mapping
                            /*  l_FCA_item_number :=
                                     'UK_FCA_'
                                  || REPLACE (l_requested_prog_revenue,
                                              'US ',
                                              '');               --l_owner_prog;

                              */
                            IF l_fca_waiver_flag <= 0
                            THEN
                                L_FCA :=
                                    NVL (get_fca (p_line_id,
                                                  l_contract_number,
                                                  l_owner_prog,
                                                  l_date, -- use one fca for all trip legs
                                                  l_currency_code),
                                         0);
                            ELSE
                                l_fca := 0;
                            END IF;

                            DBMS_OUTPUT.put_line (
                                   '-------- 6.1.3 get tier hourly rate2: '
                                || l_hourly_rate
                                || ' , FCA:'
                                || l_FCA_item_number
                                || ',  l_fca_waiver_flag'
                                || l_fca_waiver_flag
                                || ', l_fca'
                                || l_fca);
                        -- end tier pricing.
                        --=======================================

                        ELSE
                            --SYSDATE);

                            -- 1115 frax use owner prog.
                            --0614 added the override

                            DBMS_OUTPUT.put_line (
                                   '-------- 6.2 PSA OV '
                                || NVL (c.psa_ssa_override, 'N')
                                || ' ,order_number:'
                                || c.order_number);

                            -------------------------------------------------------------------------------------------
                            -- psa-->std/preferred
                            -- 0623 fixed psa override issue
                            -- 0-- check leg psa override.
                            IF NVL (c.psa_ssa_override, 'N') = 'N'
                            THEN
                                -- check PSA ADJ LIST


                                -------------------------------------------
                                l_G650_PSA_hours :=
                                    NVL (get_G650_PSA (l_contract_number), 0);

                                IF     c.owner_prog = 'G650'
                                   AND l_G650_PSA_hours > 0
                                THEN
                                    IF l_G650_PSA_hours <= c.LEG_fly_hours -- if fly hours >= th
                                    THEN
                                        l_psa_stat := 'P';
                                    ELSE
                                        l_psa_stat := 'S';
                                    END IF;

                                    DBMS_OUTPUT.put_line (
                                           '-------- 6.4 G650 PSA OV '
                                        || NVL (l_psa_stat, 'N')
                                        || ' ,order_number:'
                                        || c.order_number);
                                ELSE
                                    -- this function included new SSA/PSA rule from Christine --0117
                                    -- this function also include the logic to read PSA ADJ LIST at contract level
                                    -- this function also include the logic to read SSA ADJ LIST at contract level -- tbdevelopped
                                    BEGIN
                                        FOR m
                                            IN c_get_trip_pp (c.order_number)
                                        LOOP
                                            l_pp := m.pp;
                                            l_total_flight_hours :=
                                                TO_NUMBER (
                                                    m.total_flight_hours);
                                            l_total_fly_hours :=
                                                TO_NUMBER (m.total_fly_hours);
                                            EXIT;
                                        END LOOP;

                                        DBMS_OUTPUT.put_line (
                                               '--- pp1:'
                                            || l_pp
                                            || ',total_flight_ours'
                                            || l_total_flight_hours
                                            || ',l_total_fly_hours'
                                            || l_total_fly_hours
                                            || ',#legs'
                                            || l_number_of_legs);


                                        SELECT COUNT (*)
                                          INTO l_number_of_legs
                                          FROM oe_order_headers      h,
                                               oe_order_lines        l,
                                               mtl_system_itemS_FVL  mtl
                                         WHERE     l.header_id = h.header_id
                                               AND h.order_number =
                                                   c.order_number
                                               AND l.inventory_item_id =
                                                   mtl.inventory_item_id
                                               AND mtl.organization_id =
                                                   fnd_global.org_id
                                               AND mtl.segment1 =
                                                   'UK_TRIP_LEG_VR';

                                        DBMS_OUTPUT.put_line (
                                               '--- pp2:'
                                            || l_pp
                                            || ',total_flight_ours'
                                            || l_total_flight_hours
                                            || ','
                                            || l_total_fly_hours
                                            || ','
                                            || l_number_of_legs);



                                        l_average_fly_hours :=
                                            ROUND (
                                                  l_total_fly_hours
                                                / NVL (l_number_of_legs, 999),
                                                2);
                                        DBMS_OUTPUT.put_line (
                                               'l_average_fly_hours:'
                                            || l_average_fly_hours);
                                    EXCEPTION
                                        WHEN OTHERS
                                        THEN
                                            DBMS_OUTPUT.put_line (
                                                   '--- errpp2:'
                                                || l_pp
                                                || ',total_flight_ours'
                                                || l_total_flight_hours
                                                || ','
                                                || l_total_fly_hours
                                                || ','
                                                || l_number_of_legs);
                                            NULL;
                                    END;

                                    DBMS_OUTPUT.put_line (
                                           '-------- 6.4.2  PSA OV:af:'
                                        || l_average_fly_hours
                                        || ' ,PP'
                                        || l_pp
                                        || ', tf:'
                                        || l_total_flight_hours);

                                    IF     l_pp = 'PP'
                                       AND (   l_total_fly_hours <= 24
                                            OR l_average_fly_hours > 3.0)
                                    THEN
                                        l_psa_stat := 'P';
                                        l_psa_override_note := 'PSA-PPO';
                                    ELSE
                                        l_psa_stat :=
                                            get_psa_stat_P2 (
                                                c.actual_from,     --from_tag,
                                                c.actual_to,         --to_tag,
                                                NVL (
                                                    l_requested_prog_revenue,
                                                    c.owner_prog),
                                                l_contract_number,
                                                l_date,
                                                p_line_id); -- contract override is here.
                                    END IF;

                                    DBMS_OUTPUT.put_line (
                                           '-------- 6.5 New PSA calculated : '
                                        || l_psa_stat);
                                END IF;
                            ELSE
                                l_psa_stat := c.psa_ssa_override;
                                l_psa_override_note := 'PSA-LEGO'; --leg_override.
                            END IF;

                            IF l_psa_stat = 'P'
                            THEN
                                l_pref_std := 'PREF';
                            ELSE
                                l_pref_std := 'STD';
                            END IF;

                            --FCA revenue item will not be derived from revenue mapping
                            l_FCA_item_number :=
                                   'UK_FCA_'
                                || REPLACE (l_requested_prog_revenue,
                                            'US ',
                                            '');               --l_owner_prog;

                            IF l_fca_waiver_flag <= 0
                            THEN
                                L_FCA :=
                                    NVL (get_fca (p_line_id,
                                                  l_contract_number,
                                                  l_owner_prog,
                                                  l_date, -- use one fca for all trip legs
                                                  l_currency_code),
                                         0);
                            ELSE
                                l_fca := 0;
                            END IF;

                            DBMS_OUTPUT.put_line (
                                   '-------- 6.6 FCA revenue NUMBER '
                                || l_FCA_item_number
                                || ',  l_fca_waiver_flag'
                                || l_fca_waiver_flag
                                || ', l_fca'
                                || l_fca);

                            ----------------------------------------------------
                            --hourly rate
                            --1. get contract hourly rate item number from mapping

                            -- !!!!need change below into a function.
                            BEGIN
                                SELECT sub_line_item, hourly_rate
                                  INTO l_hourly_rate_item, l_hourly_rate
                                  FROM XXOKS_HOURLY_RATE_V       rate,
                                       xxoks_revenue_item_map_v  map
                                 WHERE     1 = 1
                                       AND RATE.SUB_LINE_ITEM =
                                           map.CONTRACT_TERM_ITEM
                                       AND rate.contract_number =
                                           l_contract_number         --'80705'
                                       AND pref_std = l_pref_std --'STD' --PREF' --PSA/SSA                            -- can be STD/PREF
                                       AND ac = L_owner_prog --'P600' --OWNER AC                   -- CAN BE OTHER AC
                                       AND TYPE = 'FRAX' --FRAX'  -- CAN BE JCARD/FRAX
                                       AND fc_nfc_fca = 'NFC' -- CAN BE NFC/FC -- ONLY USE nFC to get single line
                                       -- AND SYSDATE >= RATE.SUB_START_DATE
                                       -- AND SYSDATE <= RATE.SUB_END_DATE;
                                       AND l_l_date >= RATE.SUB_START_DATE
                                       AND l_l_date <=
                                           RATE.SUB_END_DATE + 0.9999;
                            EXCEPTION
                                WHEN OTHERS
                                THEN
                                    l_hourly_rate := 0;
                                    NULL;
                            END;

                            l_requested_prog_revenue :=
                                REPLACE (l_requested_prog_revenue, 'US ', ''); --EZ 1115 for US L450

                            DBMS_OUTPUT.put_line (
                                   '-------- 6.7 frax HOURLY RATE:'
                                || l_hourly_rate_item
                                || ':'
                                || l_hourly_rate
                                || '  ,  Contract l_requested_prog_revenue:'
                                || l_requested_prog_revenue
                                || '  , L_L_DATE:'
                                || L_L_DATE
                                || ' , L_PREF_STD:'
                                || l_pref_std
                                || ' , L_owner_prog:'
                                || L_owner_prog);


                            p_get_con_hourly_rate (l_contract_number,
                                                   'FRAX', --p_rate_type               , -- frax/jc
                                                   l_l_date, --                   DATE,
                                                   L_owner_prog, --               VARCHAR2, -- used to match AC
                                                   c.UTC_FLY_TIME_SET, -- get string p_leg_rate_o               VARCHAR2, -- override string
                                                   l_pref_std, --               VARCHAR2, -- std/other
                                                   l_l_fc, --           OUT NUMBER,
                                                   l_l_nfc, --           OUT NUMBER,
                                                   l_l_fca, --            OUT NUMBER,
                                                   l_l_hourly_rate, --         OUT NUMBER,
                                                   l_l_hourly_rate_item, --  OUT VARCHAR2,
                                                   l_l_status); -- OUT VARCHAR2);

                            IF l_l_status = 'LEG-OV-OK'
                            THEN
                                l_fc := l_l_fc;
                                l_nfc := l_l_nfc;
                                l_fca := l_l_fca;
                                l_hourly_rate := l_l_fc + l_l_nfc;
                            END IF;

                            DBMS_OUTPUT.put_line (
                                   '-------- 5.3.2 OVERRIDE STATUS: l_l_error:'
                                || l_l_status
                                || ':'
                                || l_hourly_rate
                                || ' , l_l_fc/nfc/fca:'
                                || l_l_fc
                                || '/'
                                || l_l_nfc
                                || '/'
                                || l_l_fca
                                || ' , l_actual_prog:'
                                || l_actual_prog);

                            ----------------------

                            FOR r IN c_revenue_item_number
                            LOOP
                                CASE
                                    WHEN     r.fc_nfc_fca = 'NFC'
                                         AND r.ac = l_requested_prog_revenue --l_owner_prog
                                    THEN
                                        l_NFC_item_number := r.revenue_item;
                                    WHEN     r.fc_nfc_fca = 'FC'
                                         AND r.ac = l_requested_prog_revenue --l_owner_prog
                                    THEN
                                        l_FC_item_number := r.revenue_item;
                                    ELSE
                                        NULL;
                                END CASE;

                                DBMS_OUTPUT.put_line (
                                       '-------- 6.8 Derived NFC revenue item:'
                                    || l_NFC_item_number
                                    || ' FC:'
                                    || l_FC_item_number);
                            END LOOP;
                        END IF; -- tier pricing                             ----------------------
                    END IF;

                    ---------------------

                    -------------------------------------------------------
                    --ratio  -- fca
                    --step 1: if CARD/TP and US AC requested, set ratio=1 and fca=0  -- 0105 2023
                    IF     SUBSTR (c.requested_prog, 1, 2) = 'US'
                       AND c.contract_type IN ('JetCard', 'Trial Programme')
                    THEN
                        l_int_ratio := 1;
                        l_fca := 0;
                        l_nfc := l_hourly_rate - NVL (l_fc, 0);

                        l_ratio_override_note := ' Ratio: USJPO:1 ';

                        DBMS_OUTPUT.put_line (
                               '-------- 6.8 JC US Flat NFC:'
                            || l_NFC_item_number
                            || ':'
                            || L_NFC
                            || ' FC:'
                            || l_FC_item_number
                            || ':'
                            || L_FC
                            || ' US ratio/fca override: ratio=1, fca=0');
                    ELSE
                        -- get ratio logic
                        IF NVL (c.ratio_override, 0) <> 0 -- if leg level has override, use it
                        THEN
                            l_int_ratio := c.ratio_override;
                            l_ratio_override_note :=
                                ' Ratio: LEGO:' || C.RATIO_OVERRIDE;
                            DBMS_OUTPUT.put_line (
                                '-------- 6.9 Ratio override:' || l_int_ratio);
                        ELSE
                            IF c.tail_no = 'EUSUB'
                            THEN
                                l_int_ratio := 1;
                                l_ratio_override_note := ' Ratio: EUSUBO:1 ';
                                DBMS_OUTPUT.put_line (
                                       '-------- 6.9 Ratio EUSUB:'
                                    || l_int_ratio);
                            ELSE
                                -- 0: if SLW is applied, then 1.  if all prog samem then 1. other wise get ratio
                                -- ?? wait till sherri
                                l_rate_rule :=
                                    get_G650_PSA_rule (l_contract_number);

                                IF     c.owner_prog = 'G650'
                                   AND l_rate_rule = 'R1'
                                THEN
                                    l_int_ratio := 1; -- no ratio need to apply
                                    l_ratio_override_note :=
                                        ' Ratio: G650-R1:1 ';
                                    DBMS_OUTPUT.put_line (
                                           '-------- 6.9 Ratio override g650 r1:'
                                        || l_int_ratio);
                                ELSE
                                    IF     (   NVL (c.requestED_prog,
                                                    c.actual_prog) <>
                                               c.owner_prog
                                            OR c.owner_prog <> c.actual_prog)
                                       AND NVL (c.apply_SLW_flag, 'N') = 'N'
                                    THEN
                                        BEGIN
                                            --1. get the billing_prog
                                            l_billing_prog :=
                                                get_billing_prog (
                                                    c.requested_prog,
                                                    c.actual_prog,
                                                    c.owner_prog,
                                                    NVL (c.apply_MU_flag,
                                                         'N'));
                                            l_ratio_string :=
                                                   c.owner_prog
                                                || ' to '
                                                || l_billing_prog;
                                            DBMS_OUTPUT.put_line (
                                                   '-------- 6.10 check contract override: Billing_prog:'
                                                || l_billing_prog
                                                || ':'
                                                || l_ratio_string
                                                || ' ratio:'
                                                || l_int_ratio);


                                            --2. then get the ratio RULE from contract
                                            l_term_rules :=
                                                get_trule_from_contract (
                                                    l_contract_number,
                                                    l_ratio_string);


                                            --3. IF RULE has R then use
                                            IF l_term_rules IN
                                                   ('R', 'RH', 'HR')
                                            THEN
                                                l_int_ratio :=
                                                    get_contract_ratio (
                                                        c.ohcontract_number,
                                                           c.owner_prog
                                                        || ' to '
                                                        || l_billing_prog);
                                                l_ratio_override_note :=
                                                       ' Ratio: CON:'
                                                    || L_TERM_RULES
                                                    || ':'
                                                    || l_int_ratio;
                                            END IF;

                                            l_ratio_override_note :=
                                                   l_ratio_override_note
                                                || ', bill_prog:'
                                                || l_billing_prog;
                                            DBMS_OUTPUT.put_line (
                                                   '-------- 6.11 check CONTRACT_RATIO:'
                                                || ' Rule:'
                                                || l_term_rules
                                                || ' , Ratio:'
                                                || l_int_ratio
                                                || ' ---- completed ratio override check ............');

                                            --4. if ratio override is not applied, then use global ratio for owner ac to billing ac
                                            IF NVL (l_int_ratio, 0) = 0
                                            -- IS NULL
                                            THEN
                                                l_int_ratio :=
                                                    Get_U_D_RATIO (
                                                        c.owner_prog,
                                                        l_billing_prog,
                                                        l_date);
                                            END IF;

                                            DBMS_OUTPUT.put_line (
                                                   '-------- 6.12  global Ratio:'
                                                || l_ratio_string
                                                || '  :'
                                                || NVL (l_int_ratio, 0)
                                                || ':'
                                                || l_billing_prog
                                                || ':'
                                                || c.owner_prog);
                                        EXCEPTION
                                            WHEN OTHERS
                                            THEN
                                                l_int_ratio := 1;
                                        END;
                                    ELSE
                                        l_int_ratio := 1;
                                    END IF;
                                --
                                END IF;                     -- G650 ratio rule
                            END IF;
                        END IF;                                --leg_override;

                        l_nfc := l_hourly_rate - NVL (l_fc, 0);

                        DBMS_OUTPUT.put_line (
                               '-------- 7.1 Rate NFC:'
                            || l_NFC_item_number
                            || ':'
                            || L_NFC
                            || ' FC:'
                            || l_FC_item_number
                            || ':'
                            || L_FC);

                        -----------------------------------------------
                        -- stap 2
                        -- get hours


                        --calculate the rate:
                        --ratio is pulled from trip record.

                        -- apply fca ratio override-- round to 0
                        -- changed to FCA AMT override l_fca := ROUND (l_fca_ratio_override * l_fca, 0);
                        -- apply the fca ratio from contract
                        l_ct_fca_ov_ratio :=
                            get_contract_fca_ratio (l_contract_number);
                        DBMS_OUTPUT.put_line (
                               '-------- 7.2 FCA Contract Override ratio:'
                            || l_ct_fca_ov_ratio);

                        l_fca :=
                            ROUND (
                                  NVL (l_fca_override, l_fca)
                                * l_ct_fca_ov_ratio,
                                0);
                    END IF;

                    DBMS_OUTPUT.put_line (
                           '-------- 7.3 FCA final ratio:'
                        || l_fca
                        || '-- override ratio'
                        || l_ct_fca_ov_ratio);

                    l_bill_rate := l_fca + l_fc + l_nfc;
                    l_bill_hour_rate := -- ez 0930 rounding after ratio is applied
                        ROUND ((l_fca + l_fc + l_nfc) * NVL (l_int_ratio, 1),
                               0);



                    DBMS_OUTPUT.put_line (
                           '-------- 7.4 Billing rate (fc+nfc+fca):'
                        || l_bill_rate
                        || ', applied ratio:'
                        || l_bill_hour_rate);

                    -- process SLW
                    IF NVL (c.apply_SLW_flag, 'N') = 'Y' --AND c.leg_fly_hours < 0.8  ---
                    THEN
                        l_billing_hours := c.leg_fly_hours + 0.2; --c.leg_incremental_hours;
                    ELSE
                        l_billing_hours := GREATEST (c.leg_billing_hours, 1);
                    -- a ssume migration from camp has done all billing hours calculation.
                    -- if a short leg waiver is applied, this will show the billing hours.


                    END IF;

                    DBMS_OUTPUT.put_line (
                        '------------------------------------------------');
                    DBMS_OUTPUT.put_line ('------8.0 check hours');
                    DBMS_OUTPUT.put_line (
                           '-------- 8.1 check slw'
                        || c.apply_SLW_flag
                        || ', flyhour'
                        || c.leg_fly_hours
                        --|| ', '||to_number(c.leg_incremental_hours)+to_number(c.leg_fly_hours)
                        || l_billing_hours);

                    l_billing_subtotal :=
                        ROUND (l_billing_hours * l_bill_hour_rate, --- round before * l_int_ratio,
                                                                   2);
                    l_leg_line_number := c.leg_line_number;


                    DBMS_OUTPUT.put_line (
                           '-------- 8.2 billing total:'
                        || l_bill_hour_rate
                        || '*'
                        || l_billing_hours
                        || '='
                        || l_billing_subtotal);


                    l_omb_status := get_omb_status (c.order_number);


                    DBMS_OUTPUT.put_line (
                        '-------------------------------------------------');

                    DBMS_OUTPUT.put_line (
                           '------ 9.0 start delete/insert: omb status:'
                        || l_omb_status
                        || '; p_contract_number:'
                        || p_contract_num
                        || '; exclude flag:'
                        || c.exclude_omb_flag);

                    /*      INSERT INTO EZTEST
                                   VALUES (
                                                 ' VR 110: BEFORE delete/insert: omb status:'
                                              || l_omb_status
                                              || '; p_contract_number:'
                                              || p_contract_num
                                              || '; exclude flag:'
                                              || c.exclude_omb_flag,
                                              SYSDATE);
      */
                    DBMS_OUTPUT.put_line (
                        '------ 10.1.0 :' || l_other_override_note);

                    ---7 add Log to log tables or outputs.-- requred for insert detail
                    IF                                                      --
                       -- 1=1 or
                       (    NVL (p_contract_num, 'N') <> 'TEST'
                        AND c.exclude_omb_flag = 'N'            -- not exclude
                        AND l_omb_status = 'Draft')
                    -- price not frozen.
                    THEN                   -- as TEST mode, no need to insert.
                        DBMS_OUTPUT.put_line (
                            '------ 10.1 Start delete and insdert:....');


                        l_remarks :=
                            SUBSTR (
                                   l_billing_hours
                                || '* round('
                                || l_bill_rate              --l_bill_hour_rate
                                || '*'
                                || l_int_ratio
                                || ',2)='
                                || l_billing_subtotal
                                || ' '
                                || l_ratio_override_note
                                || ' '
                                || l_psa_override_note
                                || ' '
                                || l_other_override_note,
                                1,
                                250);

                        DELETE FROM XXOKS_TRIP_DETAIL_INFO
                              WHERE batch_id = p_line_id;

                        INSERT INTO XXOKS_TRIP_DETAIL_INFO (BATCH_ID,
                                                            CREATION_DATE,
                                                            ORG_ID,
                                                            log_note,
                                                            TRX_NUMBER,
                                                            FC,
                                                            NFC,
                                                            FCA,
                                                            BILLING_RATE,
                                                            BILLING_HOURS,
                                                            RATIO_RATE,
                                                            SLW_FLAG,
                                                            REMARKS,
                                                            FC_ITEM_NUMBER,
                                                            NFC_ITEM_NUMBER,
                                                            FCA_ITEM_NUMBER,
                                                            FC_ITEM_ID,
                                                            NFC_ITEM_ID,
                                                            FCA_ITEM_ID,
                                                            VR_ITEM_NUMBER,
                                                            CONTRACT_NUMBER,
                                                            ATTRIBUTE1,
                                                            ATTRIBUTE2,
                                                            ATTRIBUTE3,
                                                            ATTRIBUTE4,
                                                            ATTRIBUTE5,
                                                            LEG_vr_link_ID)
                                 VALUES (
                                            p_line_id,
                                            SYSDATE,
                                            fnd_global.org_id,
                                            '--VR 1. Details:',
                                            l_order_number_line_no,
                                            l_fc,
                                            l_nfc,
                                            l_fca,
                                            l_bill_rate,   --l_bill_hour_rate,
                                            l_billing_hours,
                                            l_int_ratio,
                                            l_apply_slw_flag,
                                            l_remarks,
                                            /*   l_billing_hours
                                            || '* round('
                                            || l_bill_rate  --l_bill_hour_rate
                                            || '*'
                                            || l_int_ratio
                                            || ',2)='
                                            || l_billing_subtotal,
                                            */
                                            l_FC_item_number,
                                            l_NFC_item_number,
                                            l_FCA_item_number,         --NULL,
                                            NULL,
                                            NULL,
                                            NULL,
                                            NULL,
                                            l_contract_number,
                                               'PSA Override:'
                                            || c.psa_ssa_override
                                            || ':'
                                            || l_psa_stat,             --- psa
                                               'SLW:'
                                            || c.apply_SLW_flag
                                            || ' Bprog:'
                                            || l_billing_prog
                                            || ':'
                                            || c.owner_prog,          -- ratio
                                               'FCA W FLAG:'
                                            || l_fca_waiver_flag
                                            || ', FCA ov:'
                                            || l_fca_override
                                            || ', FCA amt:'
                                            || L_fca,                   -- fca
                                            NULL,                --prepay flag
                                            NULL,
                                            l_leg_vr_link_id);



                        DBMS_OUTPUT.put_line (
                            '------ 10.1 Complete delete and insdert:....');
                    END IF;
                END IF;
            END IF;
        END LOOP;


        --5 add up leg cost and fees and Return it back

        RETURN NVL (l_billing_subtotal, 0);
    EXCEPTION
        WHEN OTHERS
        THEN
            DBMS_OUTPUT.put_line (
                '------ 10.2 Failed delete and insdert:....');
            RETURN 880;
    END GET_TRIP_LEG_VR;
