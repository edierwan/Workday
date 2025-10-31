--
-- PostgreSQL database dump
--

\restrict tlgZYvkH63ICJMwjWNvfmEspHiaEi6ONotMFpvgsstgbbbyK2morUUEWDENd7Q7

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

-- Started on 2025-11-01 01:35:18 +08

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 40 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- TOC entry 6746 (class 0 OID 0)
-- Dependencies: 40
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- TOC entry 39 (class 2615 OID 16542)
-- Name: storage; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA storage;


--
-- TOC entry 1709 (class 1247 OID 23131)
-- Name: appraisal_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.appraisal_status_enum AS ENUM (
    'draft',
    'pending_self_review',
    'self_review_completed',
    'pending_manager_review',
    'manager_review_completed',
    'pending_approval',
    'approved',
    'rejected',
    'cancelled'
);


--
-- TOC entry 1700 (class 1247 OID 22696)
-- Name: claim_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.claim_status_enum AS ENUM (
    'submitted',
    'approved',
    'rejected',
    'paid',
    'cancelled'
);


--
-- TOC entry 1697 (class 1247 OID 22687)
-- Name: employment_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.employment_status_enum AS ENUM (
    'active',
    'resigned',
    'terminated',
    'suspended'
);


--
-- TOC entry 1715 (class 1247 OID 23162)
-- Name: goal_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.goal_status_enum AS ENUM (
    'draft',
    'active',
    'completed',
    'cancelled',
    'deferred'
);


--
-- TOC entry 1703 (class 1247 OID 22708)
-- Name: overtime_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.overtime_status_enum AS ENUM (
    'pending',
    'approved',
    'rejected',
    'cancelled',
    'paid'
);


--
-- TOC entry 1718 (class 1247 OID 23174)
-- Name: rating_scale_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.rating_scale_type_enum AS ENUM (
    'numeric',
    'descriptive',
    'letter_grade'
);


--
-- TOC entry 1712 (class 1247 OID 23150)
-- Name: review_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.review_type_enum AS ENUM (
    'self',
    'manager',
    'peer',
    'subordinate',
    'final'
);


--
-- TOC entry 1588 (class 1247 OID 17415)
-- Name: buckettype; Type: TYPE; Schema: storage; Owner: -
--

CREATE TYPE storage.buckettype AS ENUM (
    'STANDARD',
    'ANALYTICS'
);


--
-- TOC entry 567 (class 1255 OID 34628)
-- Name: ap_levels_set_company_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ap_levels_set_company_id() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.company_id IS NULL) THEN
    SELECT company_id INTO NEW.company_id FROM public.approval_policies WHERE id = NEW.policy_id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 577 (class 1255 OID 20408)
-- Name: auth_company_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_company_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
    SELECT u.company_id
    FROM users u
    WHERE u.id = auth.uid()
    LIMIT 1
$$;


--
-- TOC entry 839 (class 1255 OID 36644)
-- Name: auth_company_scope(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auth_company_scope() RETURNS SETOF uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  WITH me AS (
    SELECT public.auth_company_id() AS cid
  )
  SELECT cl.descendant_id
  FROM public.company_links cl
  JOIN me ON cl.ancestor_id = me.cid;
$$;


--
-- TOC entry 545 (class 1255 OID 23718)
-- Name: calculate_appraisal_overall_rating(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_appraisal_overall_rating(p_appraisal_id uuid) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_weight DECIMAL(10,2) := 0;
    v_weighted_sum DECIMAL(10,2) := 0;
    v_competency_weight DECIMAL(5,2);
    v_goal_weight DECIMAL(5,2);
    v_final_rating DECIMAL(5,2);
BEGIN
    -- Get manager review
    WITH manager_review AS (
        SELECT id FROM appraisal_reviews 
        WHERE appraisal_id = p_appraisal_id 
        AND review_type = 'manager' 
        LIMIT 1
    )
    
    -- Calculate competency ratings weighted average
    SELECT 
        COALESCE(SUM(acr.rating * atc.weight), 0),
        COALESCE(SUM(atc.weight), 0)
    INTO v_weighted_sum, v_total_weight
    FROM appraisal_competency_ratings acr
    JOIN manager_review mr ON acr.review_id = mr.id
    JOIN appraisal_template_competencies atc ON acr.competency_id = atc.competency_id
    JOIN appraisals a ON a.id = p_appraisal_id
    WHERE atc.template_id = a.template_id;
    
    -- Add goal ratings weighted average
    SELECT 
        COALESCE(SUM(agr.rating * eg.weight), 0)
    INTO v_goal_weight
    FROM appraisal_goal_ratings agr
    JOIN manager_review mr ON agr.review_id = mr.id
    JOIN employee_goals eg ON agr.goal_id = eg.id;
    
    v_weighted_sum := v_weighted_sum + v_goal_weight;
    v_total_weight := v_total_weight + (SELECT COALESCE(SUM(weight), 0) FROM employee_goals WHERE appraisal_id = p_appraisal_id);
    
    -- Calculate final rating
    IF v_total_weight > 0 THEN
        v_final_rating := v_weighted_sum / v_total_weight;
    ELSE
        v_final_rating := 0;
    END IF;
    
    RETURN ROUND(v_final_rating, 2);
END;
$$;


--
-- TOC entry 843 (class 1255 OID 18588)
-- Name: calculate_eis(numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_eis(p_salary numeric) RETURNS TABLE(employee_contribution numeric, employer_contribution numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        ROUND(p_salary * 0.002, 2),  -- 0.2% employee
        ROUND(p_salary * 0.002, 2);  -- 0.2% employer
END;
$$;


--
-- TOC entry 638 (class 1255 OID 18496)
-- Name: calculate_epf(numeric, integer, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_epf(p_salary numeric, p_employee_age integer, p_effective_date date DEFAULT CURRENT_DATE) RETURNS TABLE(employee_contribution numeric, employer_contribution numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_age_category VARCHAR(50);
    v_epf_rate RECORD;
BEGIN
    -- Malaysia rule: different % above/below 60
    IF p_employee_age < 60 THEN
        v_age_category := 'below_60';
    ELSE
        v_age_category := 'above_60';
    END IF;

    -- find matching EPF rate row
    SELECT *
    INTO v_epf_rate
    FROM epf_rates
    WHERE age_category = v_age_category
      AND effective_from <= p_effective_date
      AND (effective_to IS NULL OR effective_to >= p_effective_date)
      AND is_active = TRUE
      AND (
            salary_threshold IS NULL
            OR p_salary <= salary_threshold
          )
    ORDER BY salary_threshold DESC NULLS LAST
    LIMIT 1;

    IF v_epf_rate IS NOT NULL THEN
        RETURN QUERY
        SELECT
            ROUND(p_salary * v_epf_rate.employee_rate, 2),
            ROUND(p_salary * v_epf_rate.employer_rate, 2);
    ELSE
        -- fallback default if no rate found
        RETURN QUERY
        SELECT
            ROUND(p_salary * 0.11, 2),
            ROUND(p_salary * 0.12, 2);
    END IF;
END;
$$;


--
-- TOC entry 776 (class 1255 OID 18634)
-- Name: calculate_pcb(numeric, numeric, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_pcb(p_monthly_income numeric, p_epf_deduction numeric, p_effective_date date DEFAULT CURRENT_DATE) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_taxable_income DECIMAL(10,2);
    v_pcb_schedule RECORD;
BEGIN
    -- taxable = income - EPF (rough LHDN practice for PCB brackets)
    v_taxable_income := p_monthly_income - p_epf_deduction;

    -- try to find matching PCB band
    SELECT *
    INTO v_pcb_schedule
    FROM pcb_tax_schedules
    WHERE monthly_income_from <= v_taxable_income
      AND monthly_income_to   >= v_taxable_income
      AND effective_from <= p_effective_date
      AND (effective_to IS NULL OR effective_to >= p_effective_date)
      AND is_active = TRUE
    LIMIT 1;

    IF v_pcb_schedule IS NOT NULL THEN
        RETURN v_pcb_schedule.monthly_tax;
    END IF;

    -- fallback if no exact band found
    RETURN 0;
END;
$$;


--
-- TOC entry 680 (class 1255 OID 18542)
-- Name: calculate_socso(numeric, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_socso(p_salary numeric, p_effective_date date DEFAULT CURRENT_DATE) RETURNS TABLE(employee_contribution numeric, employer_contribution numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_socso_rate RECORD;
BEGIN
    -- try exact salary band match first
    SELECT *
    INTO v_socso_rate
    FROM socso_contribution_rates
    WHERE wage_from < p_salary
      AND wage_to   >= p_salary
      AND effective_from <= p_effective_date
      AND (effective_to IS NULL OR effective_to >= p_effective_date)
      AND is_active = TRUE
    LIMIT 1;

    IF v_socso_rate IS NOT NULL THEN
        RETURN QUERY
        SELECT
            v_socso_rate.employee_contribution,
            v_socso_rate.employer_contribution;
    END IF;

    -- fallback: get highest active band if above table range
    SELECT *
    INTO v_socso_rate
    FROM socso_contribution_rates
    WHERE effective_from <= p_effective_date
      AND (effective_to IS NULL OR effective_to >= p_effective_date)
      AND is_active = TRUE
    ORDER BY wage_to DESC
    LIMIT 1;

    IF v_socso_rate IS NOT NULL THEN
        RETURN QUERY
        SELECT
            v_socso_rate.employee_contribution,
            v_socso_rate.employer_contribution;
    END IF;

    -- absolute fallback: 0
    RETURN QUERY
    SELECT 0::DECIMAL(10,2), 0::DECIMAL(10,2);
END;
$$;


--
-- TOC entry 530 (class 1255 OID 18428)
-- Name: calculate_working_days(date, date, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_working_days(p_start_date date, p_end_date date, p_company_id uuid) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    working_days DECIMAL(5,2) := 0;
    d DATE := p_start_date;
    is_holiday BOOLEAN;
    is_weekend BOOLEAN;
BEGIN
    WHILE d <= p_end_date LOOP
        -- weekend? (0 = Sunday, 6 = Saturday)
        is_weekend := EXTRACT(DOW FROM d) IN (0, 6);

        -- company holiday on this date?
        SELECT EXISTS (
            SELECT 1
            FROM public_holidays
            WHERE company_id = p_company_id
              AND holiday_date = d
              AND is_active = TRUE
        )
        INTO is_holiday;

        IF NOT is_weekend AND NOT is_holiday THEN
            working_days := working_days + 1;
        END IF;

        d := d + 1;
    END LOOP;

    RETURN working_days;
END;
$$;


--
-- TOC entry 755 (class 1255 OID 36645)
-- Name: company_is_in_scope(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.company_is_in_scope(_company_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.auth_company_scope() AS scope(company_id)
    WHERE scope.company_id = _company_id
  );
$$;


--
-- TOC entry 572 (class 1255 OID 23719)
-- Name: create_appraisals_for_period(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_appraisals_for_period(p_period_id uuid, p_template_id uuid, p_company_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_count INTEGER := 0;
    v_employee RECORD;
BEGIN
    FOR v_employee IN 
        SELECT e.id, e.supervisor_id
        FROM employees e
        WHERE e.company_id = p_company_id
        AND e.employment_status = 'active'
        AND e.deleted_at IS NULL
        AND NOT EXISTS (
            SELECT 1 FROM appraisals a 
            WHERE a.employee_id = e.id 
            AND a.period_id = p_period_id
            AND a.deleted_at IS NULL
        )
    LOOP
        INSERT INTO appraisals (
            company_id,
            employee_id,
            period_id,
            template_id,
            reviewer_id,
            status
        ) VALUES (
            p_company_id,
            v_employee.id,
            p_period_id,
            p_template_id,
            v_employee.supervisor_id,
            'draft'
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$;


--
-- TOC entry 584 (class 1255 OID 35734)
-- Name: employee_manager_cycle(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.employee_manager_cycle(p_employee_id uuid, p_manager_id uuid) RETURNS boolean
    LANGUAGE sql
    AS $$
  WITH RECURSIVE chain AS (
    SELECT p_manager_id AS id
    UNION ALL
    SELECT e.manager_id
    FROM public.employees e
    JOIN chain c ON e.id = c.id
    WHERE e.manager_id IS NOT NULL
  )
  SELECT EXISTS (SELECT 1 FROM chain WHERE id = p_employee_id);
$$;


--
-- TOC entry 868 (class 1255 OID 27914)
-- Name: generate_gl_for_payroll(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_gl_for_payroll(p_batch_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_company_id uuid;
  v_journal_id uuid;
  r_item RECORD;
  r_map  RECORD;
  v_cost_center uuid;
BEGIN
  -- Get tenant ID
  SELECT company_id INTO v_company_id
  FROM public.payroll_batches
  WHERE id = p_batch_id;

  -- Create header
  INSERT INTO public.gl_journal_headers(company_id, source_module, source_ref_id, description)
  VALUES (v_company_id, 'payroll', p_batch_id, 'Payroll Posting')
  RETURNING id INTO v_journal_id;

  -- Loop each payroll item
  FOR r_item IN
    SELECT pi.*, e.cost_center_id AS emp_cost_center
    FROM public.payroll_items pi
    JOIN public.employees e ON e.id = pi.employee_id
    WHERE pi.payroll_batch_id = p_batch_id
      AND pi.company_id = v_company_id
  LOOP

    -- find GL mapping
    SELECT *
    INTO r_map
    FROM public.payroll_component_gl_mappings
    WHERE company_id = v_company_id
      AND component_code = r_item.component_code
      AND is_active = true
      AND deleted_at IS NULL
    LIMIT 1;

    -- skip if no mapping
    IF r_map IS NULL THEN
      CONTINUE;
    END IF;

    -- determine cost center (mapping override > employee > null)
    v_cost_center := COALESCE(r_map.cost_center_id, r_item.emp_cost_center);

    -- Insert debit line
    INSERT INTO public.gl_journal_lines
      (company_id, journal_id, debit_gl_account_id, cost_center_id, employee_id, amount)
    VALUES
      (v_company_id, v_journal_id, r_map.debit_gl_account_id, v_cost_center, r_item.employee_id, r_item.amount);

    -- Insert credit line
    INSERT INTO public.gl_journal_lines
      (company_id, journal_id, credit_gl_account_id, cost_center_id, employee_id, amount)
    VALUES
      (v_company_id, v_journal_id, r_map.credit_gl_account_id, v_cost_center, r_item.employee_id, r_item.amount);

  END LOOP;
END;
$$;


--
-- TOC entry 666 (class 1255 OID 35849)
-- Name: get_active_policy_id(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_active_policy_id(p_company_id uuid, p_action_type text) RETURNS uuid
    LANGUAGE sql
    AS $_$
  SELECT a.policy_id
  FROM public.approval_policy_assignments a
  WHERE a.company_id = $1
    AND a.action_type = $2
    AND a.is_default = true
    AND a.deleted_at IS NULL
  ORDER BY a.effective_from DESC
  LIMIT 1;
$_$;


--
-- TOC entry 749 (class 1255 OID 35737)
-- Name: get_manager_chain(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_manager_chain(p_employee_id uuid, p_max_levels integer DEFAULT 10) RETURNS TABLE(level_no integer, manager_id uuid)
    LANGUAGE sql
    AS $$
  WITH RECURSIVE r AS (
    SELECT 1 AS level_no, e.manager_id
    FROM public.employees e
    WHERE e.id = p_employee_id

    UNION ALL
    SELECT r.level_no + 1, e.manager_id
    FROM r
    JOIN public.employees e ON e.id = r.manager_id
    WHERE r.level_no < p_max_levels AND r.manager_id IS NOT NULL
  )
  SELECT level_no, manager_id FROM r WHERE manager_id IS NOT NULL;
$$;


--
-- TOC entry 629 (class 1255 OID 34860)
-- Name: hreq_appr_set_company_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.hreq_appr_set_company_id() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.company_id IS NULL) THEN
    SELECT company_id INTO NEW.company_id
    FROM public.headcount_requests
    WHERE id = NEW.headcount_request_id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 762 (class 1255 OID 35850)
-- Name: instantiate_headcount_approvals(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.instantiate_headcount_approvals(p_headcount_request_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_company_id uuid;
  v_requester  uuid;
  v_policy_id  uuid;
  v_level      record;
  v_appr       uuid;
BEGIN
  SELECT company_id, requester_employee_id, COALESCE(policy_id, public.get_active_policy_id(company_id,'headcount_request'))
  INTO v_company_id, v_requester, v_policy_id
  FROM public.headcount_requests
  WHERE id = p_headcount_request_id;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Headcount request % not found', p_headcount_request_id;
  END IF;

  FOR v_level IN
    SELECT id, level_no
    FROM public.approval_policy_levels
    WHERE policy_id = v_policy_id
    ORDER BY level_no
  LOOP
    FOR v_appr IN
      SELECT approver_employee_id
      FROM public.resolve_policy_level_approvers(v_company_id, v_requester, v_level.id)
    LOOP
      INSERT INTO public.headcount_approvals(company_id, headcount_request_id, level_no, approver_employee_id, status)
      VALUES (v_company_id, p_headcount_request_id, v_level.level_no, v_appr, 'pending')
      ON CONFLICT DO NOTHING;
    END LOOP;
  END LOOP;
END;
$$;


--
-- TOC entry 626 (class 1255 OID 35851)
-- Name: instantiate_requisition_approvals(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.instantiate_requisition_approvals(p_job_requisition_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_company_id uuid;
  v_requester  uuid;
  v_policy_id  uuid;
  v_level      record;
  v_appr       uuid;
BEGIN
  SELECT company_id, requester_employee_id, COALESCE(policy_id, public.get_active_policy_id(company_id,'requisition'))
  INTO v_company_id, v_requester, v_policy_id
  FROM public.job_requisitions
  WHERE id = p_job_requisition_id;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Job requisition % not found', p_job_requisition_id;
  END IF;

  FOR v_level IN
    SELECT id, level_no
    FROM public.approval_policy_levels
    WHERE policy_id = v_policy_id
    ORDER BY level_no
  LOOP
    FOR v_appr IN
      SELECT approver_employee_id
      FROM public.resolve_policy_level_approvers(v_company_id, v_requester, v_level.id)
    LOOP
      INSERT INTO public.job_requisition_approvals(company_id, job_requisition_id, level_no, approver_employee_id, status)
      VALUES (v_company_id, p_job_requisition_id, v_level.level_no, v_appr, 'pending')
      ON CONFLICT DO NOTHING;
    END LOOP;
  END LOOP;
END;
$$;


--
-- TOC entry 700 (class 1255 OID 35030)
-- Name: jreq_appr_set_company_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jreq_appr_set_company_id() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.company_id IS NULL) THEN
    SELECT company_id INTO NEW.company_id
    FROM public.job_requisitions
    WHERE id = NEW.job_requisition_id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 580 (class 1255 OID 35580)
-- Name: log_approval_event(uuid, text, uuid, uuid, integer, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_approval_event(p_company_id uuid, p_action_type text, p_object_id uuid, p_approval_row_id uuid, p_level_no integer, p_approver_employee_id uuid, p_old_status text, p_new_status text, p_comment text) RETURNS void
    LANGUAGE sql
    AS $_$
  INSERT INTO public.approval_events(
    company_id, action_type, object_id, approval_row_id, level_no,
    approver_employee_id, old_status, new_status, comment, decided_at
  )
  VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9, now());
$_$;


--
-- TOC entry 533 (class 1255 OID 22988)
-- Name: log_audit_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_audit_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_old jsonb;
    v_new jsonb;
BEGIN
    -- Only audit updates where company_id exists on NEW row
    -- (skips system tables that don't have company_id)
    IF NEW.company_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_old := to_jsonb(OLD);
    v_new := to_jsonb(NEW);

    INSERT INTO public.audit_logs (
        company_id,
        user_id,
        action,
        entity_type,
        entity_id,
        old_values,
        new_values,
        created_at
    )
    VALUES (
        NEW.company_id,
        NEW.updated_by,
        TG_OP,                -- 'UPDATE'
        TG_TABLE_NAME,        -- table name
        NEW.id,
        v_old,
        v_new,
        now()
    );

    RETURN NEW;
END;
$$;


--
-- TOC entry 701 (class 1255 OID 34272)
-- Name: log_position_change(uuid, text, uuid, text, jsonb, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_position_change(p_company_id uuid, p_entity_type text, p_entity_id uuid, p_action text, p_old jsonb, p_new jsonb, p_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO public.position_history(company_id, entity_type, entity_id, action, changed_by, reason, old_row, new_row)
  VALUES (p_company_id, p_entity_type, p_entity_id, p_action, auth.uid(), p_reason, p_old, p_new);
END;
$$;


--
-- TOC entry 575 (class 1255 OID 36766)
-- Name: maintain_company_links(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.maintain_company_links() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- 1) ensure self link exists (depth=0)
  INSERT INTO public.company_links (ancestor_id, descendant_id, depth)
  SELECT NEW.id, NEW.id, 0
  ON CONFLICT DO NOTHING;

  -- 2) if parent assigned, make parent → child link (depth=1)
  IF NEW.parent_company_id IS NOT NULL THEN
    INSERT INTO public.company_links (ancestor_id, descendant_id, depth)
    SELECT NEW.parent_company_id, NEW.id, 1
    ON CONFLICT DO NOTHING;

    -- 3) inherit all ancestors from parent for deeper hierarchy
    INSERT INTO public.company_links (ancestor_id, descendant_id, depth)
    SELECT cl.ancestor_id, NEW.id, cl.depth + 1
    FROM public.company_links cl
    WHERE cl.descendant_id = NEW.parent_company_id
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;


--
-- TOC entry 715 (class 1255 OID 26996)
-- Name: next_employee_number(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_employee_number(p_company_id uuid) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  next_val bigint;
BEGIN
  -- upsert tenant row
  INSERT INTO public.company_sequences(company_id, employee_seq)
  VALUES (p_company_id, 0)
  ON CONFLICT (company_id) DO NOTHING;

  -- increment & fetch
  UPDATE public.company_sequences
  SET employee_seq = employee_seq + 1,
      updated_at = now()
  WHERE company_id = p_company_id
  RETURNING employee_seq INTO next_val;

  -- return formatted string (E00001)
  RETURN 'E' || lpad(next_val::text, 5, '0');
END;
$$;


--
-- TOC entry 568 (class 1255 OID 28030)
-- Name: next_journal_number(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_journal_number(p_company_id uuid) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  next_val bigint;
BEGIN
  -- ensure row exists
  INSERT INTO public.company_journal_sequences(company_id, last_no)
  VALUES (p_company_id, 0)
  ON CONFLICT (company_id) DO NOTHING;

  -- increment
  UPDATE public.company_journal_sequences
  SET last_no = last_no + 1,
      updated_at = now()
  WHERE company_id = p_company_id
  RETURNING last_no INTO next_val;

  -- return formatted number e.g. JRN-00001
  RETURN 'JRN-' || lpad(next_val::text, 5, '0');
END;
$$;


--
-- TOC entry 800 (class 1255 OID 27828)
-- Name: on_payroll_approved(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.on_payroll_approved() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Only run when status transitions to approved
  IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
    PERFORM public.generate_gl_for_payroll(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 842 (class 1255 OID 35507)
-- Name: ot_approvals_sync_status_text(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ot_approvals_sync_status_text() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- If caller didn't set approval_status explicitly, mirror from enum 'status'
  IF NEW.approval_status IS NULL THEN
    NEW.approval_status := NEW.status::text;
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 674 (class 1255 OID 28770)
-- Name: post_journal(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.post_journal(p_journal_id uuid, p_user_id uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_company uuid;
  v_tot_debit  numeric(14,2);
  v_tot_credit numeric(14,2);
  v_status text;
BEGIN
  SELECT company_id, status INTO v_company, v_status
  FROM public.gl_journal_headers
  WHERE id = p_journal_id;

  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Journal % not found', p_journal_id;
  END IF;

  IF v_status = 'posted' THEN
    -- already posted; no-op
    RETURN;
  END IF;

  SELECT total_debit, total_credit
  INTO v_tot_debit, v_tot_credit
  FROM public.v_gl_journal_totals
  WHERE journal_id = p_journal_id;

  IF v_tot_debit IS NULL OR v_tot_credit IS NULL OR v_tot_debit = 0 OR v_tot_credit = 0 THEN
    RAISE EXCEPTION 'Cannot post journal %: empty totals (DR %, CR %)', p_journal_id, v_tot_debit, v_tot_credit;
  END IF;

  IF v_tot_debit <> v_tot_credit THEN
    RAISE EXCEPTION 'Cannot post journal %: out of balance (DR %, CR %)', p_journal_id, v_tot_debit, v_tot_credit;
  END IF;

  UPDATE public.gl_journal_headers
  SET status = 'posted',
      posted_at = now(),
      posted_by = p_user_id
  WHERE id = p_journal_id;
END;
$$;


--
-- TOC entry 515 (class 1255 OID 28812)
-- Name: prevent_change_if_posted_header(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_change_if_posted_header() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE v_status text;
BEGIN
  SELECT status INTO v_status FROM public.gl_journal_headers WHERE id = NEW.id;
  IF v_status = 'posted' THEN
    RAISE EXCEPTION 'Journal % is posted and cannot be modified', NEW.id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 683 (class 1255 OID 28814)
-- Name: prevent_change_if_posted_lines(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_change_if_posted_lines() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE v_status text;
BEGIN
  SELECT status INTO v_status FROM public.gl_journal_headers WHERE id =
    COALESCE(NEW.journal_id, OLD.journal_id);
  IF v_status = 'posted' THEN
    RAISE EXCEPTION 'Lines of posted journal % cannot be modified', COALESCE(NEW.journal_id, OLD.journal_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- TOC entry 851 (class 1255 OID 36386)
-- Name: prevent_company_id_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_company_id_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
    RAISE EXCEPTION 'company_id is immutable once set';
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 714 (class 1255 OID 35912)
-- Name: refresh_approvals(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_approvals(p_action_type text, p_object_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF p_action_type = 'headcount_request' THEN
    -- remove pending only, keep history
    DELETE FROM public.headcount_approvals
    WHERE headcount_request_id = p_object_id
      AND status = 'pending';

    PERFORM public.instantiate_headcount_approvals(p_object_id);

  ELSIF p_action_type = 'requisition' THEN
    DELETE FROM public.job_requisition_approvals
    WHERE job_requisition_id = p_object_id
      AND status = 'pending';

    PERFORM public.instantiate_requisition_approvals(p_object_id);

  ELSE
    RAISE EXCEPTION 'refresh_approvals: unsupported action_type %', p_action_type;
  END IF;
END;
$$;


--
-- TOC entry 672 (class 1255 OID 35848)
-- Name: resolve_policy_level_approvers(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolve_policy_level_approvers(p_company_id uuid, p_requester_employee_id uuid, p_level_id uuid) RETURNS TABLE(approver_employee_id uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
  r record;
  v_chain record;
  v_tag_id uuid;
BEGIN
  SELECT *
  INTO r
  FROM public.approval_policy_levels
  WHERE id = p_level_id AND company_id = p_company_id;

  IF NOT FOUND THEN
    RETURN; -- nothing
  END IF;

  -- Scope: EMPLOYEE (explicit assignee)
  IF r.approver_scope = 'EMPLOYEE' AND r.specific_employee_id IS NOT NULL THEN
    approver_employee_id := r.specific_employee_id;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Scope: POSITION (current occupant of a specific position)
  IF r.approver_scope = 'POSITION' AND r.specific_position_id IS NOT NULL THEN
    SELECT pa.employee_id
    INTO approver_employee_id
    FROM public.position_assignments pa
    WHERE pa.position_id = r.specific_position_id
      AND pa.company_id = p_company_id
      AND pa.deleted_at IS NULL
      AND pa.status = 'active'
      AND CURRENT_DATE >= pa.start_date
      AND (pa.end_date IS NULL OR CURRENT_DATE <= pa.end_date)
    LIMIT 1;

    IF approver_employee_id IS NOT NULL THEN
      RETURN NEXT;
    END IF;
    RETURN;
  END IF;

  -- Scope: MANAGER_CHAIN (N levels up)
  IF r.approver_scope = 'MANAGER_CHAIN' AND r.hop_count IS NOT NULL THEN
    FOR v_chain IN
      SELECT * FROM public.get_manager_chain(p_requester_employee_id, r.hop_count)
      ORDER BY level_no
    LOOP
      IF v_chain.level_no = r.hop_count THEN
        approver_employee_id := v_chain.manager_id;
        RETURN NEXT;
        RETURN;
      END IF;
    END LOOP;
    RETURN;
  END IF;

  -- Scope: ROLE_BAND (nearest in manager chain whose active position has matching band)
  IF r.approver_scope = 'ROLE_BAND' AND r.role_band IS NOT NULL THEN
    FOR v_chain IN
      SELECT * FROM public.get_manager_chain(p_requester_employee_id, 10) ORDER BY level_no
    LOOP
      SELECT ap.employee_id
      INTO approver_employee_id
      FROM public.v_employee_active_position ap
      WHERE ap.company_id = p_company_id
        AND ap.employee_id = v_chain.manager_id
        AND ap.role_band = r.role_band
      LIMIT 1;

      IF approver_employee_id IS NOT NULL THEN
        RETURN NEXT;
        RETURN;
      END IF;
    END LOOP;

    -- Fallback (optional): anyone in company with that band (first found)
    SELECT ap.employee_id
    INTO approver_employee_id
    FROM public.v_employee_active_position ap
    WHERE ap.company_id = p_company_id
      AND ap.role_band = r.role_band
    LIMIT 1;

    IF approver_employee_id IS NOT NULL THEN
      RETURN NEXT;
    END IF;
    RETURN;
  END IF;

  -- Scope: FUNCTION (e.g., HRBP / Finance). Use membership table.
  IF r.approver_scope = 'FUNCTION' AND r.function_tag IS NOT NULL THEN
    SELECT aft.id INTO v_tag_id
    FROM public.approval_function_tags aft
    WHERE aft.company_id = p_company_id
      AND lower(aft.tag) = lower(r.function_tag)
      AND aft.is_active = true
    LIMIT 1;

    IF v_tag_id IS NOT NULL THEN
      FOR approver_employee_id IN
        SELECT m.employee_id
        FROM public.employee_function_memberships m
        WHERE m.company_id = p_company_id
          AND m.function_tag_id = v_tag_id
      LOOP
        RETURN NEXT; -- may yield multiple; UI can require_all or 1-of-N in app layer
      END LOOP;
    END IF;
    RETURN;
  END IF;

  -- Future: ORG_UNIT / COST_CENTER resolution hooks can be added here.

  RETURN;
END;
$$;


--
-- TOC entry 542 (class 1255 OID 24200)
-- Name: set_audit_fields(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_audit_fields() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.created_by IS NULL THEN
            NEW.created_by := auth.uid();
        END IF;
        IF NEW.updated_by IS NULL THEN
            NEW.updated_by := auth.uid();
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        NEW.updated_by := auth.uid();
        NEW.created_by := OLD.created_by;
    END IF;

    RETURN NEW;
END;
$$;


--
-- TOC entry 712 (class 1255 OID 27038)
-- Name: set_employee_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_employee_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.employee_number IS NULL OR NEW.employee_number = '' THEN
    NEW.employee_number := public.next_employee_number(NEW.company_id);
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 812 (class 1255 OID 28072)
-- Name: set_journal_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_journal_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.journal_no IS NULL OR NEW.journal_no = '' THEN
    NEW.journal_no := public.next_journal_number(NEW.company_id);
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 828 (class 1255 OID 36340)
-- Name: set_tenant_company_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_tenant_company_id() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  IF NEW.company_id IS NULL THEN
    NEW.company_id := public.auth_company_id();
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 778 (class 1255 OID 37330)
-- Name: timesheet_rollup_period(uuid, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.timesheet_rollup_period(p_company_id uuid, p_start date, p_end date) RETURNS TABLE(company_id uuid, employee_id uuid, days_recorded integer, days_worked integer, worked_minutes integer, worked_hours numeric, requested_ot_hours numeric)
    LANGUAGE sql STABLE
    AS $$
  SELECT
    d.company_id,
    d.employee_id,
    COUNT(*)                                        AS days_recorded,
    COUNT(*) FILTER (WHERE d.worked_minutes > 0)    AS days_worked,
    SUM(d.worked_minutes)                           AS worked_minutes,
    ROUND(SUM(d.worked_minutes) / 60.0, 2)          AS worked_hours,
    COALESCE(SUM(d.requested_ot_hours), 0)::numeric AS requested_ot_hours
  FROM public.v_timesheet_daily d
  WHERE d.company_id = p_company_id
    AND d.work_date >= p_start
    AND d.work_date <  p_end
  GROUP BY d.company_id, d.employee_id
$$;


--
-- TOC entry 559 (class 1255 OID 17488)
-- Name: touch_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


--
-- TOC entry 818 (class 1255 OID 35735)
-- Name: trg_employees_prevent_manager_cycle(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_employees_prevent_manager_cycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- allow NULL manager (top of org), and no-change updates
  IF TG_OP = 'UPDATE' AND NEW.manager_id IS NOT DISTINCT FROM OLD.manager_id THEN
    RETURN NEW;
  END IF;

  -- self-check already exists; still re-assert for clearer error
  IF NEW.manager_id IS NOT NULL AND NEW.manager_id = NEW.id THEN
    RAISE EXCEPTION 'An employee cannot be their own manager';
  END IF;

  -- cycle check
  IF NEW.manager_id IS NOT NULL AND public.employee_manager_cycle(NEW.id, NEW.manager_id) THEN
    RAISE EXCEPTION 'Manager assignment creates a reporting cycle';
  END IF;

  RETURN NEW;
END;
$$;


--
-- TOC entry 791 (class 1255 OID 35583)
-- Name: trg_log_event_hreq(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_log_event_hreq() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.log_approval_event(
      NEW.company_id,
      'headcount_request',
      NEW.headcount_request_id,
      NEW.id,
      NEW.level_no,
      NEW.approver_employee_id,
      OLD.status, NEW.status,
      NEW.comments
    );
  ELSIF TG_OP = 'INSERT' THEN
    PERFORM public.log_approval_event(
      NEW.company_id,
      'headcount_request',
      NEW.headcount_request_id,
      NEW.id,
      NEW.level_no,
      NEW.approver_employee_id,
      NULL, NEW.status,
      NEW.comments
    );
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 526 (class 1255 OID 35585)
-- Name: trg_log_event_jreq(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_log_event_jreq() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.log_approval_event(
      NEW.company_id,
      'requisition',
      NEW.job_requisition_id,
      NEW.id,
      NEW.level_no,
      NEW.approver_employee_id,
      OLD.status, NEW.status,
      NEW.comments
    );
  ELSIF TG_OP = 'INSERT' THEN
    PERFORM public.log_approval_event(
      NEW.company_id,
      'requisition',
      NEW.job_requisition_id,
      NEW.id,
      NEW.level_no,
      NEW.approver_employee_id,
      NULL, NEW.status,
      NEW.comments
    );
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 704 (class 1255 OID 35581)
-- Name: trg_log_event_ot(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_log_event_ot() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_old text := COALESCE(OLD.approval_status, OLD.status::text);
  v_new text := COALESCE(NEW.approval_status, NEW.status::text);
BEGIN
  IF TG_OP = 'UPDATE' AND v_old IS DISTINCT FROM v_new THEN
    PERFORM public.log_approval_event(
      NEW.company_id,
      'overtime',
      NEW.overtime_request_id,
      NEW.id,
      NULL,                                   -- no levels for OT (today)
      NEW.approver_employee_id,
      v_old, v_new,
      NEW.comments
    );
  ELSIF TG_OP = 'INSERT' THEN
    PERFORM public.log_approval_event(
      NEW.company_id,
      'overtime',
      NEW.overtime_request_id,
      NEW.id,
      NULL,
      NEW.approver_employee_id,
      NULL, COALESCE(NEW.approval_status, NEW.status::text),
      NEW.comments
    );
  END IF;
  RETURN NEW;
END;
$$;


--
-- TOC entry 796 (class 1255 OID 34275)
-- Name: trg_pos_assign_history_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_pos_assign_history_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_company_id uuid;
BEGIN
  v_company_id := COALESCE(NEW.company_id, OLD.company_id);
  IF (TG_OP = 'INSERT') THEN
    PERFORM public.log_position_change(v_company_id, 'assignment', NEW.id, 'insert', NULL, to_jsonb(NEW), NULL);
    RETURN NEW;
  ELSIF (TG_OP = 'UPDATE') THEN
    PERFORM public.log_position_change(v_company_id, 'assignment', NEW.id, 'update', to_jsonb(OLD), to_jsonb(NEW), NULL);
    RETURN NEW;
  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM public.log_position_change(v_company_id, 'assignment', OLD.id, 'delete', to_jsonb(OLD), NULL, NULL);
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;


--
-- TOC entry 549 (class 1255 OID 34273)
-- Name: trg_positions_history_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_positions_history_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    PERFORM public.log_position_change(NEW.company_id, 'position', NEW.id, 'insert', NULL, to_jsonb(NEW), NULL);
    RETURN NEW;
  ELSIF (TG_OP = 'UPDATE') THEN
    PERFORM public.log_position_change(NEW.company_id, 'position', NEW.id, 'update', to_jsonb(OLD), to_jsonb(NEW), NULL);
    RETURN NEW;
  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM public.log_position_change(OLD.company_id, 'position', OLD.id, 'delete', to_jsonb(OLD), NULL, NULL);
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;


--
-- TOC entry 786 (class 1255 OID 23703)
-- Name: update_appraisal_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_appraisal_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- TOC entry 612 (class 1255 OID 33112)
-- Name: update_attendance_minutes(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_attendance_minutes(p_attendance_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  r RECORD;
  v_start time;
  v_end   time;
  v_in    timestamptz;
  v_out   timestamptz;
  late    int := 0;
  early   int := 0;
  otm     int := 0;
BEGIN
  SELECT ar.*, st.start_time AS tpl_start, st.end_time AS tpl_end,
         es.start_time_override AS o_start, es.end_time_override AS o_end
  INTO r
  FROM public.attendance_records ar
  LEFT JOIN public.employee_shifts es ON es.id = ar.shift_assignment_id
  LEFT JOIN public.shift_templates st ON st.id = COALESCE(ar.shift_template_id, es.shift_template_id)
  WHERE ar.id = p_attendance_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'attendance % not found', p_attendance_id;
  END IF;

  -- choose baseline times (override > template)
  v_start := COALESCE(r.o_start, r.tpl_start);
  v_end   := COALESCE(r.o_end,   r.tpl_end);

  v_in  := r.clock_in_time;
  v_out := r.clock_out_time;

  -- compute late
  IF v_in IS NOT NULL AND v_start IS NOT NULL THEN
    late := GREATEST(0, EXTRACT(EPOCH FROM (v_in::time - v_start))::int / 60);
  END IF;

  -- compute early leave
  IF v_out IS NOT NULL AND v_end IS NOT NULL THEN
    early := GREATEST(0, EXTRACT(EPOCH FROM (v_end - v_out::time))::int / 60);
  END IF;

  -- basic OT: time beyond planned end
  IF v_out IS NOT NULL AND v_end IS NOT NULL THEN
    otm := GREATEST(0, EXTRACT(EPOCH FROM (v_out::time - v_end))::int / 60);
  END IF;

  UPDATE public.attendance_records
  SET late_minutes = late,
      early_leave_minutes = early,
      ot_minutes = otm
  WHERE id = p_attendance_id;
END;
$$;


--
-- TOC entry 741 (class 1255 OID 33113)
-- Name: validate_attendance_geofence(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_attendance_geofence(p_attendance_id uuid, p_geo_location_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  r RECORD;
  d_m numeric(8,2);
BEGIN
  SELECT ar.*, gl.latitude AS glat, gl.longitude AS glon, gl.radius_meters
  INTO r
  FROM public.attendance_records ar
  JOIN public.geo_locations gl ON gl.id = p_geo_location_id
  WHERE ar.id = p_attendance_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'attendance % or geo location % not found', p_attendance_id, p_geo_location_id;
  END IF;

  IF ar.clock_in_latitude IS NULL OR ar.clock_in_longitude IS NULL THEN
    -- no GPS; mark failed but keep distance null
    UPDATE public.attendance_records
    SET geo_location_id = p_geo_location_id,
        geofence_distance_m = NULL,
        geo_validated = false
    WHERE id = p_attendance_id;
    RETURN;
  END IF;

  -- Haversine (approx in meters)
  WITH params AS (
    SELECT
      radians(ar.clock_in_latitude)   AS lat1,
      radians(ar.clock_in_longitude)  AS lon1,
      radians(gl.latitude)            AS lat2,
      radians(gl.longitude)           AS lon2,
      6371000.0::numeric              AS R
    FROM public.attendance_records ar, public.geo_locations gl
    WHERE ar.id = p_attendance_id AND gl.id = p_geo_location_id
  ), calc AS (
    SELECT
      2 * R * asin( sqrt( sin((lat2-lat1)/2)^2 + cos(lat1)*cos(lat2)*sin((lon2-lon1)/2)^2 ) ) AS dist_m
    FROM params
  )
  SELECT dist_m INTO d_m FROM calc;

  UPDATE public.attendance_records
  SET geo_location_id = p_geo_location_id,
      geofence_distance_m = d_m,
      geo_validated = (d_m <= r.radius_meters)
  WHERE id = p_attendance_id;
END;
$$;


--
-- TOC entry 578 (class 1255 OID 17387)
-- Name: add_prefixes(text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.add_prefixes(_bucket_id text, _name text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    prefixes text[];
BEGIN
    prefixes := "storage"."get_prefixes"("_name");

    IF array_length(prefixes, 1) > 0 THEN
        INSERT INTO storage.prefixes (name, bucket_id)
        SELECT UNNEST(prefixes) as name, "_bucket_id" ON CONFLICT DO NOTHING;
    END IF;
END;
$$;


--
-- TOC entry 679 (class 1255 OID 17296)
-- Name: can_insert_object(text, text, uuid, jsonb); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


--
-- TOC entry 750 (class 1255 OID 17433)
-- Name: delete_leaf_prefixes(text[], text[]); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.delete_leaf_prefixes(bucket_ids text[], names text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_rows_deleted integer;
BEGIN
    LOOP
        WITH candidates AS (
            SELECT DISTINCT
                t.bucket_id,
                unnest(storage.get_prefixes(t.name)) AS name
            FROM unnest(bucket_ids, names) AS t(bucket_id, name)
        ),
        uniq AS (
             SELECT
                 bucket_id,
                 name,
                 storage.get_level(name) AS level
             FROM candidates
             WHERE name <> ''
             GROUP BY bucket_id, name
        ),
        leaf AS (
             SELECT
                 p.bucket_id,
                 p.name,
                 p.level
             FROM storage.prefixes AS p
                  JOIN uniq AS u
                       ON u.bucket_id = p.bucket_id
                           AND u.name = p.name
                           AND u.level = p.level
             WHERE NOT EXISTS (
                 SELECT 1
                 FROM storage.objects AS o
                 WHERE o.bucket_id = p.bucket_id
                   AND o.level = p.level + 1
                   AND o.name COLLATE "C" LIKE p.name || '/%'
             )
             AND NOT EXISTS (
                 SELECT 1
                 FROM storage.prefixes AS c
                 WHERE c.bucket_id = p.bucket_id
                   AND c.level = p.level + 1
                   AND c.name COLLATE "C" LIKE p.name || '/%'
             )
        )
        DELETE
        FROM storage.prefixes AS p
            USING leaf AS l
        WHERE p.bucket_id = l.bucket_id
          AND p.name = l.name
          AND p.level = l.level;

        GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;
        EXIT WHEN v_rows_deleted = 0;
    END LOOP;
END;
$$;


--
-- TOC entry 522 (class 1255 OID 17388)
-- Name: delete_prefix(text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.delete_prefix(_bucket_id text, _name text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    -- Check if we can delete the prefix
    IF EXISTS(
        SELECT FROM "storage"."prefixes"
        WHERE "prefixes"."bucket_id" = "_bucket_id"
          AND level = "storage"."get_level"("_name") + 1
          AND "prefixes"."name" COLLATE "C" LIKE "_name" || '/%'
        LIMIT 1
    )
    OR EXISTS(
        SELECT FROM "storage"."objects"
        WHERE "objects"."bucket_id" = "_bucket_id"
          AND "storage"."get_level"("objects"."name") = "storage"."get_level"("_name") + 1
          AND "objects"."name" COLLATE "C" LIKE "_name" || '/%'
        LIMIT 1
    ) THEN
    -- There are sub-objects, skip deletion
    RETURN false;
    ELSE
        DELETE FROM "storage"."prefixes"
        WHERE "prefixes"."bucket_id" = "_bucket_id"
          AND level = "storage"."get_level"("_name")
          AND "prefixes"."name" = "_name";
        RETURN true;
    END IF;
END;
$$;


--
-- TOC entry 564 (class 1255 OID 17392)
-- Name: delete_prefix_hierarchy_trigger(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.delete_prefix_hierarchy_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    prefix text;
BEGIN
    prefix := "storage"."get_prefix"(OLD."name");

    IF coalesce(prefix, '') != '' THEN
        PERFORM "storage"."delete_prefix"(OLD."bucket_id", prefix);
    END IF;

    RETURN OLD;
END;
$$;


--
-- TOC entry 661 (class 1255 OID 17412)
-- Name: enforce_bucket_name_length(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.enforce_bucket_name_length() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


--
-- TOC entry 792 (class 1255 OID 17257)
-- Name: extension(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts,1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


--
-- TOC entry 716 (class 1255 OID 17256)
-- Name: filename(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


--
-- TOC entry 656 (class 1255 OID 17255)
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


--
-- TOC entry 794 (class 1255 OID 17369)
-- Name: get_level(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_level(name text) RETURNS integer
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT array_length(string_to_array("name", '/'), 1);
$$;


--
-- TOC entry 780 (class 1255 OID 17385)
-- Name: get_prefix(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_prefix(name text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT
    CASE WHEN strpos("name", '/') > 0 THEN
             regexp_replace("name", '[\/]{1}[^\/]+\/?$', '')
         ELSE
             ''
        END;
$_$;


--
-- TOC entry 795 (class 1255 OID 17386)
-- Name: get_prefixes(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_prefixes(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
    parts text[];
    prefixes text[];
    prefix text;
BEGIN
    -- Split the name into parts by '/'
    parts := string_to_array("name", '/');
    prefixes := '{}';

    -- Construct the prefixes, stopping one level below the last part
    FOR i IN 1..array_length(parts, 1) - 1 LOOP
            prefix := array_to_string(parts[1:i], '/');
            prefixes := array_append(prefixes, prefix);
    END LOOP;

    RETURN prefixes;
END;
$$;


--
-- TOC entry 610 (class 1255 OID 17410)
-- Name: get_size_by_bucket(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_size_by_bucket() RETURNS TABLE(size bigint, bucket_id text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


--
-- TOC entry 717 (class 1255 OID 17340)
-- Name: list_multipart_uploads_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text) RETURNS TABLE(key text, id text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


--
-- TOC entry 802 (class 1255 OID 17303)
-- Name: list_objects_with_delimiter(text, text, text, integer, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_objects_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text) RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(name COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                        substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1)))
                    ELSE
                        name
                END AS name, id, metadata, updated_at
            FROM
                storage.objects
            WHERE
                bucket_id = $5 AND
                name ILIKE $1 || ''%'' AND
                CASE
                    WHEN $6 != '''' THEN
                    name COLLATE "C" > $6
                ELSE true END
                AND CASE
                    WHEN $4 != '''' THEN
                        CASE
                            WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                                substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                name COLLATE "C" > $4
                            END
                    ELSE
                        true
                END
            ORDER BY
                name COLLATE "C" ASC) as e order by name COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_token, bucket_id, start_after;
END;
$_$;


--
-- TOC entry 845 (class 1255 OID 17432)
-- Name: lock_top_prefixes(text[], text[]); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.lock_top_prefixes(bucket_ids text[], names text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_bucket text;
    v_top text;
BEGIN
    FOR v_bucket, v_top IN
        SELECT DISTINCT t.bucket_id,
            split_part(t.name, '/', 1) AS top
        FROM unnest(bucket_ids, names) AS t(bucket_id, name)
        WHERE t.name <> ''
        ORDER BY 1, 2
        LOOP
            PERFORM pg_advisory_xact_lock(hashtextextended(v_bucket || '/' || v_top, 0));
        END LOOP;
END;
$$;


--
-- TOC entry 827 (class 1255 OID 17434)
-- Name: objects_delete_cleanup(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.objects_delete_cleanup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_bucket_ids text[];
    v_names      text[];
BEGIN
    IF current_setting('storage.gc.prefixes', true) = '1' THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('storage.gc.prefixes', '1', true);

    SELECT COALESCE(array_agg(d.bucket_id), '{}'),
           COALESCE(array_agg(d.name), '{}')
    INTO v_bucket_ids, v_names
    FROM deleted AS d
    WHERE d.name <> '';

    PERFORM storage.lock_top_prefixes(v_bucket_ids, v_names);
    PERFORM storage.delete_leaf_prefixes(v_bucket_ids, v_names);

    RETURN NULL;
END;
$$;


--
-- TOC entry 603 (class 1255 OID 17391)
-- Name: objects_insert_prefix_trigger(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.objects_insert_prefix_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    NEW.level := "storage"."get_level"(NEW."name");

    RETURN NEW;
END;
$$;


--
-- TOC entry 824 (class 1255 OID 17435)
-- Name: objects_update_cleanup(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.objects_update_cleanup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    -- NEW - OLD (destinations to create prefixes for)
    v_add_bucket_ids text[];
    v_add_names      text[];

    -- OLD - NEW (sources to prune)
    v_src_bucket_ids text[];
    v_src_names      text[];
BEGIN
    IF TG_OP <> 'UPDATE' THEN
        RETURN NULL;
    END IF;

    -- 1) Compute NEW−OLD (added paths) and OLD−NEW (moved-away paths)
    WITH added AS (
        SELECT n.bucket_id, n.name
        FROM new_rows n
        WHERE n.name <> '' AND position('/' in n.name) > 0
        EXCEPT
        SELECT o.bucket_id, o.name FROM old_rows o WHERE o.name <> ''
    ),
    moved AS (
         SELECT o.bucket_id, o.name
         FROM old_rows o
         WHERE o.name <> ''
         EXCEPT
         SELECT n.bucket_id, n.name FROM new_rows n WHERE n.name <> ''
    )
    SELECT
        -- arrays for ADDED (dest) in stable order
        COALESCE( (SELECT array_agg(a.bucket_id ORDER BY a.bucket_id, a.name) FROM added a), '{}' ),
        COALESCE( (SELECT array_agg(a.name      ORDER BY a.bucket_id, a.name) FROM added a), '{}' ),
        -- arrays for MOVED (src) in stable order
        COALESCE( (SELECT array_agg(m.bucket_id ORDER BY m.bucket_id, m.name) FROM moved m), '{}' ),
        COALESCE( (SELECT array_agg(m.name      ORDER BY m.bucket_id, m.name) FROM moved m), '{}' )
    INTO v_add_bucket_ids, v_add_names, v_src_bucket_ids, v_src_names;

    -- Nothing to do?
    IF (array_length(v_add_bucket_ids, 1) IS NULL) AND (array_length(v_src_bucket_ids, 1) IS NULL) THEN
        RETURN NULL;
    END IF;

    -- 2) Take per-(bucket, top) locks: ALL prefixes in consistent global order to prevent deadlocks
    DECLARE
        v_all_bucket_ids text[];
        v_all_names text[];
    BEGIN
        -- Combine source and destination arrays for consistent lock ordering
        v_all_bucket_ids := COALESCE(v_src_bucket_ids, '{}') || COALESCE(v_add_bucket_ids, '{}');
        v_all_names := COALESCE(v_src_names, '{}') || COALESCE(v_add_names, '{}');

        -- Single lock call ensures consistent global ordering across all transactions
        IF array_length(v_all_bucket_ids, 1) IS NOT NULL THEN
            PERFORM storage.lock_top_prefixes(v_all_bucket_ids, v_all_names);
        END IF;
    END;

    -- 3) Create destination prefixes (NEW−OLD) BEFORE pruning sources
    IF array_length(v_add_bucket_ids, 1) IS NOT NULL THEN
        WITH candidates AS (
            SELECT DISTINCT t.bucket_id, unnest(storage.get_prefixes(t.name)) AS name
            FROM unnest(v_add_bucket_ids, v_add_names) AS t(bucket_id, name)
            WHERE name <> ''
        )
        INSERT INTO storage.prefixes (bucket_id, name)
        SELECT c.bucket_id, c.name
        FROM candidates c
        ON CONFLICT DO NOTHING;
    END IF;

    -- 4) Prune source prefixes bottom-up for OLD−NEW
    IF array_length(v_src_bucket_ids, 1) IS NOT NULL THEN
        -- re-entrancy guard so DELETE on prefixes won't recurse
        IF current_setting('storage.gc.prefixes', true) <> '1' THEN
            PERFORM set_config('storage.gc.prefixes', '1', true);
        END IF;

        PERFORM storage.delete_leaf_prefixes(v_src_bucket_ids, v_src_names);
    END IF;

    RETURN NULL;
END;
$$;


--
-- TOC entry 528 (class 1255 OID 17440)
-- Name: objects_update_level_trigger(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.objects_update_level_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Ensure this is an update operation and the name has changed
    IF TG_OP = 'UPDATE' AND (NEW."name" <> OLD."name" OR NEW."bucket_id" <> OLD."bucket_id") THEN
        -- Set the new level
        NEW."level" := "storage"."get_level"(NEW."name");
    END IF;
    RETURN NEW;
END;
$$;


--
-- TOC entry 699 (class 1255 OID 17411)
-- Name: objects_update_prefix_trigger(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.objects_update_prefix_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    old_prefixes TEXT[];
BEGIN
    -- Ensure this is an update operation and the name has changed
    IF TG_OP = 'UPDATE' AND (NEW."name" <> OLD."name" OR NEW."bucket_id" <> OLD."bucket_id") THEN
        -- Retrieve old prefixes
        old_prefixes := "storage"."get_prefixes"(OLD."name");

        -- Remove old prefixes that are only used by this object
        WITH all_prefixes as (
            SELECT unnest(old_prefixes) as prefix
        ),
        can_delete_prefixes as (
             SELECT prefix
             FROM all_prefixes
             WHERE NOT EXISTS (
                 SELECT 1 FROM "storage"."objects"
                 WHERE "bucket_id" = OLD."bucket_id"
                   AND "name" <> OLD."name"
                   AND "name" LIKE (prefix || '%')
             )
         )
        DELETE FROM "storage"."prefixes" WHERE name IN (SELECT prefix FROM can_delete_prefixes);

        -- Add new prefixes
        PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    END IF;
    -- Set the new level
    NEW."level" := "storage"."get_level"(NEW."name");

    RETURN NEW;
END;
$$;


--
-- TOC entry 524 (class 1255 OID 17368)
-- Name: operation(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.operation() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


--
-- TOC entry 754 (class 1255 OID 17436)
-- Name: prefixes_delete_cleanup(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.prefixes_delete_cleanup() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_bucket_ids text[];
    v_names      text[];
BEGIN
    IF current_setting('storage.gc.prefixes', true) = '1' THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('storage.gc.prefixes', '1', true);

    SELECT COALESCE(array_agg(d.bucket_id), '{}'),
           COALESCE(array_agg(d.name), '{}')
    INTO v_bucket_ids, v_names
    FROM deleted AS d
    WHERE d.name <> '';

    PERFORM storage.lock_top_prefixes(v_bucket_ids, v_names);
    PERFORM storage.delete_leaf_prefixes(v_bucket_ids, v_names);

    RETURN NULL;
END;
$$;


--
-- TOC entry 514 (class 1255 OID 17390)
-- Name: prefixes_insert_trigger(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.prefixes_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    RETURN NEW;
END;
$$;


--
-- TOC entry 858 (class 1255 OID 17284)
-- Name: search(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql
    AS $$
declare
    can_bypass_rls BOOLEAN;
begin
    SELECT rolbypassrls
    INTO can_bypass_rls
    FROM pg_roles
    WHERE rolname = coalesce(nullif(current_setting('role', true), 'none'), current_user);

    IF can_bypass_rls THEN
        RETURN QUERY SELECT * FROM storage.search_v1_optimised(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    ELSE
        RETURN QUERY SELECT * FROM storage.search_legacy_v1(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    END IF;
end;
$$;


--
-- TOC entry 582 (class 1255 OID 17408)
-- Name: search_legacy_v1(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select path_tokens[$1] as folder
           from storage.objects
             where objects.name ilike $2 || $3 || ''%''
               and bucket_id = $4
               and array_length(objects.path_tokens, 1) <> $1
           group by folder
           order by folder ' || v_sort_order || '
     )
     (select folder as "name",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


--
-- TOC entry 862 (class 1255 OID 17407)
-- Name: search_v1_optimised(text, text, integer, integer, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_v1_optimised(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select (string_to_array(name, ''/''))[level] as name
           from storage.prefixes
             where lower(prefixes.name) like lower($2 || $3) || ''%''
               and bucket_id = $4
               and level = $1
           order by name ' || v_sort_order || '
     )
     (select name,
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[level] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where lower(objects.name) like lower($2 || $3) || ''%''
       and bucket_id = $4
       and level = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


--
-- TOC entry 857 (class 1255 OID 17431)
-- Name: search_v2(text, text, integer, integer, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer DEFAULT 100, levels integer DEFAULT 1, start_after text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, sort_column text DEFAULT 'name'::text, sort_column_after text DEFAULT ''::text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    sort_col text;
    sort_ord text;
    cursor_op text;
    cursor_expr text;
    sort_expr text;
BEGIN
    -- Validate sort_order
    sort_ord := lower(sort_order);
    IF sort_ord NOT IN ('asc', 'desc') THEN
        sort_ord := 'asc';
    END IF;

    -- Determine cursor comparison operator
    IF sort_ord = 'asc' THEN
        cursor_op := '>';
    ELSE
        cursor_op := '<';
    END IF;
    
    sort_col := lower(sort_column);
    -- Validate sort column  
    IF sort_col IN ('updated_at', 'created_at') THEN
        cursor_expr := format(
            '($5 = '''' OR ROW(date_trunc(''milliseconds'', %I), name COLLATE "C") %s ROW(COALESCE(NULLIF($6, '''')::timestamptz, ''epoch''::timestamptz), $5))',
            sort_col, cursor_op
        );
        sort_expr := format(
            'COALESCE(date_trunc(''milliseconds'', %I), ''epoch''::timestamptz) %s, name COLLATE "C" %s',
            sort_col, sort_ord, sort_ord
        );
    ELSE
        cursor_expr := format('($5 = '''' OR name COLLATE "C" %s $5)', cursor_op);
        sort_expr := format('name COLLATE "C" %s', sort_ord);
    END IF;

    RETURN QUERY EXECUTE format(
        $sql$
        SELECT * FROM (
            (
                SELECT
                    split_part(name, '/', $4) AS key,
                    name,
                    NULL::uuid AS id,
                    updated_at,
                    created_at,
                    NULL::timestamptz AS last_accessed_at,
                    NULL::jsonb AS metadata
                FROM storage.prefixes
                WHERE name COLLATE "C" LIKE $1 || '%%'
                    AND bucket_id = $2
                    AND level = $4
                    AND %s
                ORDER BY %s
                LIMIT $3
            )
            UNION ALL
            (
                SELECT
                    split_part(name, '/', $4) AS key,
                    name,
                    id,
                    updated_at,
                    created_at,
                    last_accessed_at,
                    metadata
                FROM storage.objects
                WHERE name COLLATE "C" LIKE $1 || '%%'
                    AND bucket_id = $2
                    AND level = $4
                    AND %s
                ORDER BY %s
                LIMIT $3
            )
        ) obj
        ORDER BY %s
        LIMIT $3
        $sql$,
        cursor_expr,    -- prefixes WHERE
        sort_expr,      -- prefixes ORDER BY
        cursor_expr,    -- objects WHERE
        sort_expr,      -- objects ORDER BY
        sort_expr       -- final ORDER BY
    )
    USING prefix, bucket_name, limits, levels, start_after, sort_column_after;
END;
$_$;


--
-- TOC entry 723 (class 1255 OID 17285)
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 433 (class 1259 OID 23587)
-- Name: appraisal_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisal_approvals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    appraisal_id uuid NOT NULL,
    approver_id uuid NOT NULL,
    approval_level integer NOT NULL,
    status character varying(50) DEFAULT 'pending'::character varying,
    comments text,
    approved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 6747 (class 0 OID 0)
-- Dependencies: 433
-- Name: TABLE appraisal_approvals; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisal_approvals IS 'Approval workflow tracking';


--
-- TOC entry 435 (class 1259 OID 23642)
-- Name: appraisal_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisal_comments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    appraisal_id uuid NOT NULL,
    user_id uuid NOT NULL,
    comment text NOT NULL,
    is_private boolean DEFAULT false,
    parent_comment_id uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);


--
-- TOC entry 6748 (class 0 OID 0)
-- Dependencies: 435
-- Name: TABLE appraisal_comments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisal_comments IS 'Discussion comments on appraisals';


--
-- TOC entry 431 (class 1259 OID 23538)
-- Name: appraisal_competency_ratings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisal_competency_ratings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    review_id uuid NOT NULL,
    competency_id uuid NOT NULL,
    rating numeric(5,2),
    comments text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    company_id uuid NOT NULL
);


--
-- TOC entry 6749 (class 0 OID 0)
-- Dependencies: 431
-- Name: TABLE appraisal_competency_ratings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisal_competency_ratings IS 'Ratings for individual competencies';


--
-- TOC entry 6750 (class 0 OID 0)
-- Dependencies: 431
-- Name: COLUMN appraisal_competency_ratings.company_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.appraisal_competency_ratings.company_id IS 'Tenant/company scope for RLS';


--
-- TOC entry 434 (class 1259 OID 23616)
-- Name: appraisal_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisal_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    appraisal_id uuid NOT NULL,
    document_name character varying(500) NOT NULL,
    document_type character varying(100),
    file_path text NOT NULL,
    file_size integer,
    uploaded_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);


--
-- TOC entry 6751 (class 0 OID 0)
-- Dependencies: 434
-- Name: TABLE appraisal_documents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisal_documents IS 'Documents attached to appraisals';


--
-- TOC entry 432 (class 1259 OID 23562)
-- Name: appraisal_goal_ratings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisal_goal_ratings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    review_id uuid NOT NULL,
    goal_id uuid NOT NULL,
    achievement_percentage numeric(5,2),
    rating numeric(5,2),
    comments text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    company_id uuid NOT NULL,
    CONSTRAINT chk_achievement_range CHECK (((achievement_percentage >= (0)::numeric) AND (achievement_percentage <= (100)::numeric)))
);


--
-- TOC entry 6752 (class 0 OID 0)
-- Dependencies: 432
-- Name: TABLE appraisal_goal_ratings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisal_goal_ratings IS 'Ratings for individual goals';


--
-- TOC entry 6753 (class 0 OID 0)
-- Dependencies: 432
-- Name: COLUMN appraisal_goal_ratings.company_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.appraisal_goal_ratings.company_id IS 'Tenant/company scope for RLS';


--
-- TOC entry 436 (class 1259 OID 23676)
-- Name: appraisal_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisal_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    appraisal_id uuid NOT NULL,
    changed_by uuid,
    change_type character varying(100) NOT NULL,
    old_value jsonb,
    new_value jsonb,
    notes text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 6754 (class 0 OID 0)
-- Dependencies: 436
-- Name: TABLE appraisal_history; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisal_history IS 'Audit trail for appraisal changes';


--
-- TOC entry 420 (class 1259 OID 23181)
-- Name: appraisal_periods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisal_periods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    start_date date NOT NULL,
    end_date date NOT NULL,
    self_review_deadline date,
    manager_review_deadline date,
    final_approval_deadline date,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_appraisal_period_dates CHECK ((end_date > start_date))
);


--
-- TOC entry 6755 (class 0 OID 0)
-- Dependencies: 420
-- Name: TABLE appraisal_periods; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisal_periods IS 'Defines appraisal cycles and periods';


--
-- TOC entry 430 (class 1259 OID 23506)
-- Name: appraisal_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisal_reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    appraisal_id uuid NOT NULL,
    reviewer_id uuid NOT NULL,
    review_type public.review_type_enum NOT NULL,
    overall_rating numeric(5,2),
    overall_comments text,
    strengths text,
    areas_for_improvement text,
    submitted_at timestamp with time zone,
    is_submitted boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 6756 (class 0 OID 0)
-- Dependencies: 430
-- Name: TABLE appraisal_reviews; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisal_reviews IS 'Reviews from different parties (self, manager, peer, etc.)';


--
-- TOC entry 426 (class 1259 OID 23349)
-- Name: appraisal_template_competencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisal_template_competencies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    competency_id uuid NOT NULL,
    weight numeric(5,2) DEFAULT 0.00,
    is_required boolean DEFAULT true,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    company_id uuid NOT NULL
);


--
-- TOC entry 6757 (class 0 OID 0)
-- Dependencies: 426
-- Name: TABLE appraisal_template_competencies; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisal_template_competencies IS 'Links competencies to templates';


--
-- TOC entry 6758 (class 0 OID 0)
-- Dependencies: 426
-- Name: COLUMN appraisal_template_competencies.company_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.appraisal_template_competencies.company_id IS 'Tenant/company scope for RLS';


--
-- TOC entry 423 (class 1259 OID 23264)
-- Name: appraisal_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisal_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    rating_scale_id uuid,
    is_360_enabled boolean DEFAULT false,
    enable_goals boolean DEFAULT true,
    enable_competencies boolean DEFAULT true,
    enable_comments boolean DEFAULT true,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 6759 (class 0 OID 0)
-- Dependencies: 423
-- Name: TABLE appraisal_templates; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisal_templates IS 'Templates defining appraisal structure';


--
-- TOC entry 427 (class 1259 OID 23373)
-- Name: appraisals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appraisals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    period_id uuid NOT NULL,
    template_id uuid NOT NULL,
    reviewer_id uuid,
    status public.appraisal_status_enum DEFAULT 'draft'::public.appraisal_status_enum,
    self_review_submitted_at timestamp with time zone,
    manager_review_submitted_at timestamp with time zone,
    final_approved_at timestamp with time zone,
    final_rating numeric(5,2),
    overall_comments text,
    strengths text,
    areas_for_improvement text,
    development_plan text,
    recommended_action character varying(100),
    salary_increase_percentage numeric(5,2),
    bonus_amount numeric(12,2),
    promotion_recommended boolean DEFAULT false,
    approved_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 6760 (class 0 OID 0)
-- Dependencies: 427
-- Name: TABLE appraisals; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.appraisals IS 'Main appraisal records for employees';


--
-- TOC entry 503 (class 1259 OID 35570)
-- Name: approval_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    action_type text NOT NULL,
    object_id uuid NOT NULL,
    approval_row_id uuid,
    level_no integer,
    approver_employee_id uuid,
    old_status text,
    new_status text,
    decided_at timestamp with time zone DEFAULT now(),
    comment text
);


--
-- TOC entry 502 (class 1259 OID 35120)
-- Name: approval_function_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_function_tags (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    tag text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 495 (class 1259 OID 34582)
-- Name: approval_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_policies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    action_type text NOT NULL,
    name text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_ap_policies_action_type CHECK ((action_type = ANY (ARRAY['leave'::text, 'overtime'::text, 'attendance_exception'::text, 'headcount_request'::text, 'requisition'::text, 'roster_change'::text])))
);


--
-- TOC entry 497 (class 1259 OID 34636)
-- Name: approval_policy_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_policy_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    action_type text NOT NULL,
    policy_id uuid NOT NULL,
    cost_center_id uuid,
    org_unit_id uuid,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    is_default boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_ap_assign_action_type CHECK ((action_type = ANY (ARRAY['leave'::text, 'overtime'::text, 'attendance_exception'::text, 'headcount_request'::text, 'requisition'::text, 'roster_change'::text])))
);


--
-- TOC entry 496 (class 1259 OID 34607)
-- Name: approval_policy_levels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_policy_levels (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    policy_id uuid NOT NULL,
    level_no integer NOT NULL,
    approver_scope text NOT NULL,
    role_band text,
    function_tag text,
    specific_position_id uuid,
    specific_employee_id uuid,
    org_unit_id uuid,
    cost_center_id uuid,
    hop_count integer,
    min_value numeric,
    max_value numeric,
    require_all boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    CONSTRAINT chk_ap_levels_level_no CHECK (((level_no >= 1) AND (level_no <= 10))),
    CONSTRAINT chk_ap_levels_role_band CHECK (((role_band IS NULL) OR (role_band = ANY (ARRAY['executive'::text, 'manager'::text, 'supervisor'::text, 'staff'::text])))),
    CONSTRAINT chk_ap_levels_scope CHECK ((approver_scope = ANY (ARRAY['ROLE_BAND'::text, 'FUNCTION'::text, 'POSITION'::text, 'EMPLOYEE'::text, 'ORG_UNIT'::text, 'COST_CENTER'::text, 'MANAGER_CHAIN'::text]))),
    CONSTRAINT chk_ap_levels_thresholds CHECK (((min_value IS NULL) OR (max_value IS NULL) OR (min_value <= max_value)))
);


--
-- TOC entry 482 (class 1259 OID 32612)
-- Name: attendance_exceptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_exceptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    work_date date NOT NULL,
    attendance_record_id uuid,
    exception_type text NOT NULL,
    minutes_affected integer DEFAULT 0,
    reason text,
    attachment_path text,
    status text DEFAULT 'pending'::text NOT NULL,
    approver_id uuid,
    decided_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_attn_exc_minutes CHECK (((minutes_affected IS NULL) OR (minutes_affected >= 0))),
    CONSTRAINT chk_attn_exc_status CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text]))),
    CONSTRAINT chk_attn_exc_type CHECK ((exception_type = ANY (ARRAY['late'::text, 'early_leave'::text, 'absent'::text, 'missed_punch'::text, 'other'::text])))
);


--
-- TOC entry 6761 (class 0 OID 0)
-- Dependencies: 482
-- Name: TABLE attendance_exceptions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.attendance_exceptions IS 'Justifications for late/early/absent/missed punch with approvals and audit.';


--
-- TOC entry 483 (class 1259 OID 32778)
-- Name: attendance_qr_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_qr_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    geo_location_id uuid,
    label text,
    token text NOT NULL,
    rotation_seconds integer DEFAULT 60 NOT NULL,
    valid_from timestamp with time zone DEFAULT now() NOT NULL,
    valid_to timestamp with time zone,
    is_active boolean DEFAULT true NOT NULL,
    max_uses_per_token integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 412 (class 1259 OID 22058)
-- Name: attendance_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    work_date date NOT NULL,
    clock_in_time timestamp with time zone,
    clock_in_method text,
    clock_in_ip text,
    clock_in_location text,
    clock_out_time timestamp with time zone,
    clock_out_method text,
    clock_out_ip text,
    clock_out_location text,
    status text DEFAULT 'present'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    shift_assignment_id uuid,
    shift_template_id uuid,
    geo_location_id uuid,
    device_id uuid,
    geo_validated boolean DEFAULT false,
    device_validated boolean DEFAULT false,
    qr_validated boolean DEFAULT false,
    geofence_distance_m numeric(8,2),
    late_minutes integer DEFAULT 0,
    early_leave_minutes integer DEFAULT 0,
    ot_minutes integer DEFAULT 0,
    is_ot_approved boolean DEFAULT false,
    is_on_leave boolean DEFAULT false,
    clock_in_latitude numeric(10,7),
    clock_in_longitude numeric(10,7),
    clock_out_latitude numeric(10,7),
    clock_out_longitude numeric(10,7),
    CONSTRAINT chk_attendance_geo_dist_nonneg CHECK (((geofence_distance_m IS NULL) OR (geofence_distance_m >= (0)::numeric))),
    CONSTRAINT chk_attendance_minutes_nonneg CHECK (((COALESCE(late_minutes, 0) >= 0) AND (COALESCE(early_leave_minutes, 0) >= 0) AND (COALESCE(ot_minutes, 0) >= 0)))
);


--
-- TOC entry 6762 (class 0 OID 0)
-- Dependencies: 412
-- Name: TABLE attendance_records; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.attendance_records IS 'Daily attendance with links to shift assignment/template, geo/device validation and OT/leave flags.';


--
-- TOC entry 481 (class 1259 OID 32426)
-- Name: attendance_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    grace_late_mins integer DEFAULT 5 NOT NULL,
    grace_early_leave_mins integer DEFAULT 0 NOT NULL,
    rounding_in_mins integer DEFAULT 0 NOT NULL,
    rounding_out_mins integer DEFAULT 0 NOT NULL,
    require_geo boolean DEFAULT false NOT NULL,
    require_device_trust boolean DEFAULT false NOT NULL,
    require_qr_kiosk boolean DEFAULT false NOT NULL,
    selfie_required boolean DEFAULT false NOT NULL,
    geofence_mode text DEFAULT 'warn'::text NOT NULL,
    default_location_id uuid,
    treat_weekend_as_nonworking boolean DEFAULT true NOT NULL,
    ot_auto boolean DEFAULT false NOT NULL,
    ot_threshold_minutes integer DEFAULT 0 NOT NULL,
    office_ip_allowlist cidr[],
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    CONSTRAINT chk_geofence_mode CHECK ((geofence_mode = ANY (ARRAY['off'::text, 'warn'::text, 'enforce'::text]))),
    CONSTRAINT chk_rounding_values CHECK (((rounding_in_mins = ANY (ARRAY[0, 5, 10, 15, 30])) AND (rounding_out_mins = ANY (ARRAY[0, 5, 10, 15, 30]))))
);


--
-- TOC entry 6763 (class 0 OID 0)
-- Dependencies: 481
-- Name: TABLE attendance_rules; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.attendance_rules IS 'Per-company attendance policies: grace/rounding, capture requirements, geofencing, OT hints, IP allowlist.';


--
-- TOC entry 487 (class 1259 OID 33012)
-- Name: attendance_scan_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_scan_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid,
    attendance_record_id uuid,
    scan_type text NOT NULL,
    method text NOT NULL,
    status text DEFAULT 'success'::text NOT NULL,
    reason text,
    source_ip inet,
    user_agent text,
    device_id uuid,
    qr_token_id uuid,
    kiosk_session_id uuid,
    latitude numeric(10,7),
    longitude numeric(10,7),
    distance_m numeric(8,2),
    geo_location_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_scan_distance_nonneg CHECK (((distance_m IS NULL) OR (distance_m >= (0)::numeric))),
    CONSTRAINT chk_scan_method CHECK ((method = ANY (ARRAY['mobile'::text, 'web'::text, 'kiosk'::text, 'api'::text]))),
    CONSTRAINT chk_scan_status CHECK ((status = ANY (ARRAY['success'::text, 'reject'::text, 'warn'::text]))),
    CONSTRAINT chk_scan_type CHECK ((scan_type = ANY (ARRAY['clock_in'::text, 'clock_out'::text, 'qr_check'::text, 'geo_check'::text, 'device_trust'::text, 'manual_adjust'::text])))
);


--
-- TOC entry 392 (class 1259 OID 17575)
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    user_id uuid,
    action character varying(100) NOT NULL,
    entity_type character varying(100),
    entity_id uuid,
    old_values jsonb,
    new_values jsonb,
    ip_address inet,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    table_name text,
    record_id uuid,
    changed_fields text[],
    deleted_at timestamp with time zone,
    created_by uuid,
    updated_by uuid
);


--
-- TOC entry 414 (class 1259 OID 22176)
-- Name: claim_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.claim_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    description text,
    requires_receipt boolean DEFAULT true NOT NULL,
    max_amount_per_claim numeric(12,2),
    max_claims_per_month integer,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 389 (class 1259 OID 17490)
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(200) NOT NULL,
    registration_number character varying(50),
    ssm_registration_date date,
    tax_id character varying(50),
    tax_reference_number character varying(20),
    epf_employer_number character varying(30),
    epf_office_code character varying(10),
    socso_employer_number character varying(30),
    socso_office_code character varying(10),
    eis_employer_number character varying(30),
    hrdf_reference_number character varying(30),
    email character varying(100),
    phone character varying(30),
    website character varying(200),
    address_line1 character varying(200),
    address_line2 character varying(200),
    city character varying(100),
    state character varying(100),
    postcode character varying(10),
    country character varying(50) DEFAULT 'Malaysia'::character varying,
    subscription_plan_id uuid,
    subscription_status character varying(20) DEFAULT 'active'::character varying,
    subscription_start_date date,
    subscription_end_date date,
    trial_ends_at timestamp with time zone,
    max_employees integer DEFAULT 25,
    default_currency character(3) DEFAULT 'MYR'::bpchar,
    timezone character varying(50) DEFAULT 'Asia/Kuala_Lumpur'::character varying,
    date_format character varying(20) DEFAULT 'DD/MM/YYYY'::character varying,
    time_format character varying(10) DEFAULT '24h'::character varying,
    language character varying(10) DEFAULT 'en'::character varying,
    payroll_cutoff_day integer DEFAULT 25,
    payroll_payment_day integer DEFAULT 25,
    auto_calculate_overtime boolean DEFAULT true,
    is_active boolean DEFAULT true,
    is_deleted boolean DEFAULT false,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    data_encryption_enabled boolean DEFAULT false NOT NULL,
    created_by uuid,
    updated_by uuid,
    parent_company_id uuid
);


--
-- TOC entry 448 (class 1259 OID 27978)
-- Name: company_journal_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_journal_sequences (
    company_id uuid NOT NULL,
    last_no bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 507 (class 1259 OID 36520)
-- Name: company_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_links (
    ancestor_id uuid NOT NULL,
    descendant_id uuid NOT NULL,
    depth integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 417 (class 1259 OID 22358)
-- Name: company_notification_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_notification_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    event_type text NOT NULL,
    enable_email boolean DEFAULT true NOT NULL,
    enable_sms boolean DEFAULT false NOT NULL,
    enable_whatsapp boolean DEFAULT false NOT NULL,
    enable_push boolean DEFAULT false NOT NULL,
    enable_in_app boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 443 (class 1259 OID 26944)
-- Name: company_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_sequences (
    company_id uuid NOT NULL,
    employee_seq bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 425 (class 1259 OID 23323)
-- Name: competencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.competencies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    category_id uuid,
    name character varying(255) NOT NULL,
    description text,
    display_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);


--
-- TOC entry 6764 (class 0 OID 0)
-- Dependencies: 425
-- Name: TABLE competencies; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.competencies IS 'Individual competencies to evaluate';


--
-- TOC entry 424 (class 1259 OID 23303)
-- Name: competency_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.competency_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    display_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);


--
-- TOC entry 6765 (class 0 OID 0)
-- Dependencies: 424
-- Name: TABLE competency_categories; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.competency_categories IS 'Categories for grouping competencies';


--
-- TOC entry 442 (class 1259 OID 26708)
-- Name: cost_centers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cost_centers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT cost_centers_code_check CHECK ((code ~ '^[A-Z0-9._-]{2,32}$'::text))
);


--
-- TOC entry 419 (class 1259 OID 22995)
-- Name: db_meta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.db_meta (
    id integer NOT NULL,
    schema_version text NOT NULL,
    applied_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 418 (class 1259 OID 22994)
-- Name: db_meta_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.db_meta_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 6766 (class 0 OID 0)
-- Dependencies: 418
-- Name: db_meta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.db_meta_id_seq OWNED BY public.db_meta.id;


--
-- TOC entry 393 (class 1259 OID 18740)
-- Name: departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name character varying(100) NOT NULL,
    code character varying(20),
    description text,
    parent_department_id uuid,
    manager_id uuid,
    cost_center character varying(50),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 480 (class 1259 OID 32356)
-- Name: device_register; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_register (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid,
    device_label text NOT NULL,
    device_type text DEFAULT 'mobile'::text NOT NULL,
    platform text,
    device_fingerprint text,
    ip_address inet,
    is_trusted boolean DEFAULT false NOT NULL,
    is_kiosk boolean DEFAULT false NOT NULL,
    last_seen_at timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_device_type CHECK ((device_type = ANY (ARRAY['mobile'::text, 'web'::text, 'kiosk'::text, 'tablet'::text])))
);


--
-- TOC entry 450 (class 1259 OID 29238)
-- Name: employee_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_actions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    action_type text NOT NULL,
    action_date date DEFAULT CURRENT_DATE NOT NULL,
    effective_date date NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 452 (class 1259 OID 29382)
-- Name: employee_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_addresses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    address_type text DEFAULT 'home'::text NOT NULL,
    street text,
    city text,
    state text,
    postal_code text,
    country text DEFAULT 'Malaysia'::text,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    valid_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 396 (class 1259 OID 19036)
-- Name: employee_allowances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_allowances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    allowance_code character varying(50),
    allowance_name character varying(100) NOT NULL,
    description text,
    amount numeric(10,2) NOT NULL,
    is_recurring boolean DEFAULT true,
    is_taxable boolean DEFAULT true,
    is_epf_included boolean DEFAULT true,
    is_socso_included boolean DEFAULT true,
    is_eis_included boolean DEFAULT true,
    effective_from date NOT NULL,
    effective_to date,
    payroll_note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 455 (class 1259 OID 29608)
-- Name: employee_bank_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_bank_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    bank_name text NOT NULL,
    bank_code text,
    account_holder_name text NOT NULL,
    account_number text NOT NULL,
    iban text,
    swift_code text,
    is_primary boolean DEFAULT true NOT NULL,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    valid_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 415 (class 1259 OID 22207)
-- Name: employee_claims; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_claims (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    claim_type_id uuid NOT NULL,
    claim_date date NOT NULL,
    amount numeric(12,2) NOT NULL,
    currency text DEFAULT 'MYR'::text,
    description text,
    receipt_url text,
    receipt_verified boolean DEFAULT false NOT NULL,
    status public.claim_status_enum DEFAULT 'submitted'::public.claim_status_enum NOT NULL,
    approver_id uuid,
    approval_notes text,
    paid_in_payroll_batch_id uuid,
    paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 454 (class 1259 OID 29519)
-- Name: employee_compensation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_compensation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    currency text DEFAULT 'MYR'::text NOT NULL,
    pay_frequency text DEFAULT 'monthly'::text NOT NULL,
    base_salary numeric(14,2) DEFAULT 0 NOT NULL,
    allowance_housing numeric(14,2) DEFAULT 0,
    allowance_transport numeric(14,2) DEFAULT 0,
    allowance_other numeric(14,2) DEFAULT 0,
    grade text,
    level text,
    step text,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    valid_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 397 (class 1259 OID 19144)
-- Name: employee_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    document_type character varying(50) NOT NULL,
    document_category character varying(50),
    document_name character varying(200) NOT NULL,
    file_url character varying(500) NOT NULL,
    file_size integer,
    file_type character varying(50),
    expiry_date date,
    is_confidential boolean DEFAULT false,
    is_deleted boolean DEFAULT false,
    deleted_at timestamp with time zone,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    uploaded_by uuid,
    notes text,
    created_by uuid,
    updated_by uuid
);


--
-- TOC entry 505 (class 1259 OID 35818)
-- Name: employee_function_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_function_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    function_tag_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 428 (class 1259 OID 23432)
-- Name: employee_goals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_goals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    appraisal_id uuid,
    period_id uuid,
    title character varying(500) NOT NULL,
    description text,
    target_completion_date date,
    weight numeric(5,2) DEFAULT 0.00,
    status public.goal_status_enum DEFAULT 'draft'::public.goal_status_enum,
    progress_percentage numeric(5,2) DEFAULT 0.00,
    is_carry_forward boolean DEFAULT false,
    parent_goal_id uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_progress_range CHECK (((progress_percentage >= (0)::numeric) AND (progress_percentage <= (100)::numeric)))
);


--
-- TOC entry 6767 (class 0 OID 0)
-- Dependencies: 428
-- Name: TABLE employee_goals; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.employee_goals IS 'Goals and KPIs assigned to employees';


--
-- TOC entry 398 (class 1259 OID 19218)
-- Name: employee_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    change_type character varying(50) NOT NULL,
    previous_department_id uuid,
    previous_position_id uuid,
    previous_manager_id uuid,
    previous_salary numeric(10,2),
    previous_employment_status character varying(50),
    new_department_id uuid,
    new_position_id uuid,
    new_manager_id uuid,
    new_salary numeric(10,2),
    new_employment_status character varying(50),
    effective_date date NOT NULL,
    reason text,
    notes text,
    workflow_reference text,
    approved_by uuid,
    approved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    deleted_at timestamp with time zone,
    updated_by uuid
);


--
-- TOC entry 451 (class 1259 OID 29302)
-- Name: employee_job_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_job_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    org_unit uuid,
    department_id uuid,
    cost_center_id uuid,
    position_title text,
    job_grade text,
    employment_type text,
    manager_id uuid,
    work_location_id uuid,
    valid_from date NOT NULL,
    valid_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    position_id uuid
);


--
-- TOC entry 465 (class 1259 OID 31012)
-- Name: employee_leave_entitlements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_leave_entitlements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    leave_type_id uuid NOT NULL,
    policy_id uuid NOT NULL,
    entitled_days numeric(6,2) DEFAULT 0 NOT NULL,
    opening_balance numeric(6,2) DEFAULT 0,
    carry_forward_days numeric(6,2) DEFAULT 0,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    source text DEFAULT 'policy'::text,
    remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 411 (class 1259 OID 20216)
-- Name: employee_loans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_loans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    loan_type character varying(50),
    loan_amount numeric(10,2) NOT NULL,
    interest_rate numeric(5,2) DEFAULT 0,
    monthly_deduction numeric(10,2) NOT NULL,
    total_paid numeric(10,2) DEFAULT 0,
    remaining_balance numeric(10,2) GENERATED ALWAYS AS ((loan_amount - total_paid)) STORED,
    loan_date date NOT NULL,
    first_deduction_date date NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying,
    approved_by uuid,
    approved_at timestamp with time zone,
    reason text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 441 (class 1259 OID 24352)
-- Name: employee_shift_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_shift_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    work_date date NOT NULL,
    shift_template_id uuid NOT NULL,
    work_location_id uuid,
    planned_start_time time without time zone,
    planned_end_time time without time zone,
    notes text,
    status text DEFAULT 'scheduled'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 478 (class 1259 OID 32210)
-- Name: employee_shifts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_shifts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    work_date date NOT NULL,
    shift_template_id uuid,
    start_time_override time without time zone,
    end_time_override time without time zone,
    break_minutes_override integer,
    status text DEFAULT 'assigned'::text NOT NULL,
    assignment_source text DEFAULT 'manual'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_emp_shifts_status CHECK ((status = ANY (ARRAY['assigned'::text, 'swapped'::text, 'cancelled'::text, 'on_leave'::text, 'holiday'::text]))),
    CONSTRAINT chk_emp_shifts_times CHECK (((start_time_override IS NULL) OR (end_time_override IS NULL) OR (start_time_override <> end_time_override)))
);


--
-- TOC entry 6768 (class 0 OID 0)
-- Dependencies: 478
-- Name: TABLE employee_shifts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.employee_shifts IS 'Daily roster assignment: connects an employee to a shift (template + per-day overrides).';


--
-- TOC entry 453 (class 1259 OID 29448)
-- Name: employee_work_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_work_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    schedule_type text DEFAULT 'full_time'::text NOT NULL,
    shift_code text,
    work_location text DEFAULT 'office'::text,
    work_days text[] DEFAULT ARRAY['mon'::text, 'tue'::text, 'wed'::text, 'thu'::text, 'fri'::text],
    start_time time without time zone DEFAULT '09:00:00'::time without time zone,
    end_time time without time zone DEFAULT '18:00:00'::time without time zone,
    break_minutes integer DEFAULT 60,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    valid_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 395 (class 1259 OID 18898)
-- Name: employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_number character varying(50) NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    full_name character varying(200) GENERATED ALWAYS AS ((((first_name)::text || ' '::text) || (last_name)::text)) STORED,
    ic_number character varying(20),
    passport_number character varying(20),
    date_of_birth date NOT NULL,
    gender character varying(20),
    nationality character varying(50) DEFAULT 'Malaysian'::character varying,
    race character varying(50),
    religion character varying(50),
    marital_status character varying(20),
    sensitive_data_consent_at timestamp with time zone,
    email character varying(100),
    phone_number character varying(20),
    mobile_number character varying(20),
    emergency_contact_name character varying(100),
    emergency_contact_phone character varying(20),
    emergency_contact_relationship character varying(50),
    address_line1 character varying(200),
    address_line2 character varying(200),
    city character varying(100),
    state character varying(50),
    postcode character varying(10),
    country character varying(50) DEFAULT 'Malaysia'::character varying,
    department_id uuid,
    position_id uuid,
    manager_id uuid,
    employment_type character varying(50),
    employment_status public.employment_status_enum DEFAULT 'active'::public.employment_status_enum,
    join_date date NOT NULL,
    probation_months integer DEFAULT 3,
    confirmation_date date,
    resignation_date date,
    last_working_date date,
    termination_date date,
    termination_reason text,
    basic_salary numeric(10,2),
    currency character varying(3) DEFAULT 'MYR'::character varying,
    pay_frequency character varying(20) DEFAULT 'monthly'::character varying,
    epf_number character varying(30),
    socso_number character varying(30),
    eis_number character varying(30),
    tax_number character varying(30),
    bank_name character varying(100),
    bank_account_number character varying(50),
    bank_account_holder_name character varying(200),
    work_location character varying(200),
    work_email character varying(100),
    profile_picture_url character varying(500),
    is_deleted boolean DEFAULT false,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    ic_encrypted boolean DEFAULT false NOT NULL,
    salary_encrypted boolean DEFAULT false NOT NULL,
    cost_center_id uuid,
    hire_date date,
    probation_end_on date,
    phone_mobile text,
    work_location_id uuid,
    base_salary numeric(14,2),
    salary_effective_from date,
    pay_schedule text,
    epf_no text,
    socso_no text,
    income_tax_no text,
    num_dependents integer,
    CONSTRAINT chk_employees_currency_iso4217 CHECK (((currency IS NULL) OR ((currency)::text ~ '^[A-Z]{3}$'::text))),
    CONSTRAINT chk_employees_manager_not_self CHECK (((manager_id IS NULL) OR (manager_id <> id))),
    CONSTRAINT chk_employees_num_dependents_nonneg CHECK (((num_dependents IS NULL) OR (num_dependents >= 0))),
    CONSTRAINT chk_employees_pay_schedule_allowed CHECK (((pay_schedule IS NULL) OR (pay_schedule = ANY (ARRAY['monthly'::text, 'biweekly'::text, 'weekly'::text])))),
    CONSTRAINT chk_employees_probation_after_hire CHECK (((probation_end_on IS NULL) OR (hire_date IS NULL) OR (probation_end_on >= hire_date))),
    CONSTRAINT chk_employees_term_after_hire CHECK (((termination_date IS NULL) OR (hire_date IS NULL) OR (termination_date >= hire_date))),
    CONSTRAINT ck_employee_dates CHECK ((((confirmation_date IS NULL) OR (join_date <= confirmation_date)) AND ((resignation_date IS NULL) OR (join_date <= resignation_date)) AND ((termination_date IS NULL) OR (join_date <= termination_date)))),
    CONSTRAINT ck_ic_format CHECK (((ic_number IS NULL) OR ((ic_number)::text ~ '^[0-9]{6}-[0-9]{2}-[0-9]{4}$'::text)))
);


--
-- TOC entry 6769 (class 0 OID 0)
-- Dependencies: 395
-- Name: COLUMN employees.currency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.currency IS 'ISO 4217 (e.g., MYR, USD)';


--
-- TOC entry 6770 (class 0 OID 0)
-- Dependencies: 395
-- Name: COLUMN employees.cost_center_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.cost_center_id IS 'Optional: allocate employee to a cost center (tenant-scoped).';


--
-- TOC entry 6771 (class 0 OID 0)
-- Dependencies: 395
-- Name: COLUMN employees.pay_schedule; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.pay_schedule IS 'Payroll cadence: monthly/biweekly/weekly';


--
-- TOC entry 408 (class 1259 OID 20179)
-- Name: epf_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.epf_rates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    age_category character varying(50) NOT NULL,
    salary_threshold numeric(10,2),
    employee_rate numeric(5,4) NOT NULL,
    employer_rate numeric(5,4) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    created_by uuid,
    updated_by uuid
);


--
-- TOC entry 479 (class 1259 OID 32290)
-- Name: geo_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geo_locations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name text NOT NULL,
    location_type text DEFAULT 'office'::text NOT NULL,
    latitude numeric(10,7) NOT NULL,
    longitude numeric(10,7) NOT NULL,
    radius_meters integer DEFAULT 150 NOT NULL,
    timezone character varying(50) DEFAULT 'Asia/Kuala_Lumpur'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    notes text,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_geo_location_type CHECK ((location_type = ANY (ARRAY['office'::text, 'site'::text, 'store'::text, 'remote'::text])))
);


--
-- TOC entry 444 (class 1259 OID 27352)
-- Name: gl_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gl_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    description text,
    normal_side text DEFAULT 'debit'::text NOT NULL,
    category text,
    is_postable boolean DEFAULT true NOT NULL,
    parent_id uuid,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT gl_accounts_category_check CHECK (((category IS NULL) OR (category = ANY (ARRAY['asset'::text, 'liability'::text, 'equity'::text, 'income'::text, 'expense'::text])))),
    CONSTRAINT gl_accounts_code_check CHECK ((code ~ '^[A-Z0-9._-]{2,32}$'::text)),
    CONSTRAINT gl_accounts_normal_side_check CHECK ((normal_side = ANY (ARRAY['debit'::text, 'credit'::text])))
);


--
-- TOC entry 446 (class 1259 OID 27508)
-- Name: gl_journal_headers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gl_journal_headers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    source_module text DEFAULT 'payroll'::text NOT NULL,
    source_ref_id uuid,
    journal_no text,
    journal_date date DEFAULT CURRENT_DATE NOT NULL,
    description text,
    status text DEFAULT 'pending'::text NOT NULL,
    export_status text,
    posted_at timestamp with time zone,
    posted_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 447 (class 1259 OID 27746)
-- Name: gl_journal_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gl_journal_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    journal_id uuid NOT NULL,
    debit_gl_account_id uuid,
    credit_gl_account_id uuid,
    cost_center_id uuid,
    employee_id uuid,
    amount numeric(14,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_gl_line_amount_pos CHECK ((amount > (0)::numeric)),
    CONSTRAINT chk_gl_line_one_side_only CHECK (((
CASE
    WHEN (debit_gl_account_id IS NOT NULL) THEN 1
    ELSE 0
END +
CASE
    WHEN (credit_gl_account_id IS NOT NULL) THEN 1
    ELSE 0
END) = 1)),
    CONSTRAINT gl_journal_lines_amount_check CHECK ((amount >= (0)::numeric))
);


--
-- TOC entry 429 (class 1259 OID 23488)
-- Name: goal_milestones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.goal_milestones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    goal_id uuid NOT NULL,
    title character varying(500) NOT NULL,
    description text,
    target_date date,
    completion_date date,
    is_completed boolean DEFAULT false,
    display_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 6772 (class 0 OID 0)
-- Dependencies: 429
-- Name: TABLE goal_milestones; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.goal_milestones IS 'Milestones for tracking goal progress';


--
-- TOC entry 499 (class 1259 OID 34840)
-- Name: headcount_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.headcount_approvals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    headcount_request_id uuid NOT NULL,
    level_no integer NOT NULL,
    approver_employee_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    comments text,
    decided_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    CONSTRAINT chk_hreq_appr_level CHECK (((level_no >= 1) AND (level_no <= 10))),
    CONSTRAINT chk_hreq_appr_status CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'skipped'::text, 'cancelled'::text])))
);


--
-- TOC entry 489 (class 1259 OID 34100)
-- Name: headcount_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.headcount_plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    cost_center_id uuid,
    org_unit_id uuid,
    plan_fte numeric(6,2) DEFAULT 0.00 NOT NULL,
    plan_cost numeric(14,2),
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_hc_plan_period CHECK ((period_start <= period_end))
);


--
-- TOC entry 498 (class 1259 OID 34748)
-- Name: headcount_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.headcount_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    requester_employee_id uuid,
    position_id uuid,
    proposed_title text,
    proposed_grade text,
    cost_center_id uuid,
    requested_fte numeric(4,2) DEFAULT 1.00 NOT NULL,
    justification text,
    urgency text DEFAULT 'normal'::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    policy_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_hreq_fte CHECK (((requested_fte > (0)::numeric) AND (requested_fte <= 5.0))),
    CONSTRAINT chk_hreq_status CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text]))),
    CONSTRAINT chk_hreq_urgency CHECK ((urgency = ANY (ARRAY['normal'::text, 'high'::text, 'critical'::text])))
);


--
-- TOC entry 473 (class 1259 OID 31578)
-- Name: holiday_calendar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.holiday_calendar (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    country_code text DEFAULT 'MY'::text NOT NULL,
    state text,
    holiday_date date NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 457 (class 1259 OID 29808)
-- Name: job_catalog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_catalog (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    job_family text NOT NULL,
    job_role text NOT NULL,
    job_grade text,
    job_level text,
    job_code text,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    valid_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 501 (class 1259 OID 35010)
-- Name: job_requisition_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_requisition_approvals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    job_requisition_id uuid NOT NULL,
    level_no integer NOT NULL,
    approver_employee_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    comments text,
    decided_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    CONSTRAINT chk_jreq_appr_level CHECK (((level_no >= 1) AND (level_no <= 10))),
    CONSTRAINT chk_jreq_appr_status CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'skipped'::text, 'cancelled'::text])))
);


--
-- TOC entry 500 (class 1259 OID 34908)
-- Name: job_requisitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_requisitions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    requester_employee_id uuid,
    hiring_manager_id uuid,
    position_id uuid,
    proposed_title text,
    proposed_grade text,
    cost_center_id uuid,
    headcount integer DEFAULT 1 NOT NULL,
    justification text,
    status text DEFAULT 'pending'::text NOT NULL,
    opened_at timestamp with time zone,
    closed_at timestamp with time zone,
    policy_id uuid,
    headcount_request_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_jreq_headcount CHECK (((headcount >= 1) AND (headcount <= 500))),
    CONSTRAINT chk_jreq_status CHECK ((status = ANY (ARRAY['draft'::text, 'pending'::text, 'approved'::text, 'open'::text, 'on_hold'::text, 'filled'::text, 'rejected'::text, 'cancelled'::text, 'closed'::text])))
);


--
-- TOC entry 484 (class 1259 OID 32848)
-- Name: kiosk_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kiosk_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    device_id uuid,
    geo_location_id uuid,
    session_label text,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone,
    is_active boolean DEFAULT true NOT NULL,
    last_heartbeat_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 476 (class 1259 OID 31782)
-- Name: leave_accrual_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_accrual_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    run_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    leave_type_id uuid NOT NULL,
    entitlement_source text DEFAULT 'policy'::text,
    accrual_days numeric(6,2) DEFAULT 0 NOT NULL,
    accrual_date date DEFAULT CURRENT_DATE NOT NULL,
    posted_to_ledger boolean DEFAULT false,
    ledger_id uuid,
    remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid
);


--
-- TOC entry 475 (class 1259 OID 31722)
-- Name: leave_accrual_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_accrual_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    run_type text DEFAULT 'auto'::text NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    triggered_by uuid,
    triggered_at timestamp with time zone DEFAULT now(),
    remarks text,
    error_details text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT leave_accrual_runs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'completed'::text, 'failed'::text])))
);


--
-- TOC entry 401 (class 1259 OID 19676)
-- Name: leave_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_applications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    leave_type_id uuid NOT NULL,
    leave_entitlement_id uuid,
    start_date date NOT NULL,
    end_date date NOT NULL,
    total_days numeric(5,2) NOT NULL,
    is_half_day boolean DEFAULT false,
    half_day_period character varying(10),
    reason text,
    attachment_url character varying(500),
    covering_employee_id uuid,
    handover_notes text,
    contact_number character varying(20),
    emergency_contact character varying(20),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    approver_id uuid,
    approval_notes text,
    approved_at timestamp with time zone,
    rejected_reason text,
    is_cancelled boolean DEFAULT false,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    cancellation_reason text,
    applied_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT ck_positive_days CHECK ((total_days > (0)::numeric)),
    CONSTRAINT ck_valid_leave_dates CHECK ((end_date >= start_date))
);


--
-- TOC entry 402 (class 1259 OID 19744)
-- Name: leave_approval_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_approval_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    leave_application_id uuid NOT NULL,
    action character varying(50) NOT NULL,
    from_status character varying(20),
    to_status character varying(20) NOT NULL,
    performed_by uuid NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    company_id uuid NOT NULL
);


--
-- TOC entry 6773 (class 0 OID 0)
-- Dependencies: 402
-- Name: COLUMN leave_approval_history.company_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_approval_history.company_id IS 'Tenant/company scope for RLS';


--
-- TOC entry 469 (class 1259 OID 31330)
-- Name: leave_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_approvals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    request_id uuid NOT NULL,
    level integer NOT NULL,
    approver_id uuid NOT NULL,
    decision text DEFAULT 'pending'::text NOT NULL,
    decided_at timestamp with time zone,
    remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT leave_approvals_decision_check CHECK ((decision = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'skipped'::text])))
);


--
-- TOC entry 404 (class 1259 OID 19791)
-- Name: leave_balance_adjustments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_balance_adjustments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    leave_entitlement_id uuid NOT NULL,
    adjustment_type character varying(50) NOT NULL,
    adjustment_days numeric(5,2) NOT NULL,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    deleted_at timestamp with time zone,
    updated_by uuid
);


--
-- TOC entry 466 (class 1259 OID 31090)
-- Name: leave_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_balances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    leave_type_id uuid NOT NULL,
    year integer NOT NULL,
    opening_balance numeric(6,2) DEFAULT 0,
    credited numeric(6,2) DEFAULT 0,
    used numeric(6,2) DEFAULT 0,
    adjusted numeric(6,2) DEFAULT 0,
    carry_forward numeric(6,2) DEFAULT 0,
    remaining numeric(6,2) GENERATED ALWAYS AS (((((opening_balance + credited) + carry_forward) + adjusted) - used)) STORED,
    last_updated timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 403 (class 1259 OID 19765)
-- Name: leave_blackout_periods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_blackout_periods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name character varying(200) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    applies_to_all boolean DEFAULT true,
    department_ids uuid[],
    position_ids uuid[],
    reason text,
    allow_emergency_leave boolean DEFAULT true,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    deleted_at timestamp with time zone,
    updated_by uuid,
    CONSTRAINT ck_blackout_dates CHECK ((end_date >= start_date))
);


--
-- TOC entry 470 (class 1259 OID 31402)
-- Name: leave_cancel_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_cancel_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    request_id uuid NOT NULL,
    cancelled_by uuid NOT NULL,
    cancelled_at timestamp with time zone DEFAULT now() NOT NULL,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 400 (class 1259 OID 19598)
-- Name: leave_entitlements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_entitlements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    leave_type_id uuid NOT NULL,
    year integer NOT NULL,
    entitled_days numeric(5,2) DEFAULT 0 NOT NULL,
    carried_forward numeric(5,2) DEFAULT 0,
    additional_days numeric(5,2) DEFAULT 0,
    used_days numeric(5,2) DEFAULT 0,
    pending_days numeric(5,2) DEFAULT 0,
    available_days numeric(5,2) GENERATED ALWAYS AS (((((entitled_days + carried_forward) + additional_days) - used_days) - pending_days)) STORED,
    carried_forward_expires_at date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    created_by uuid,
    updated_by uuid,
    CONSTRAINT ck_non_negative_days CHECK (((entitled_days >= (0)::numeric) AND (carried_forward >= (0)::numeric) AND (used_days >= (0)::numeric) AND (pending_days >= (0)::numeric)))
);


--
-- TOC entry 467 (class 1259 OID 31162)
-- Name: leave_ledger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_ledger (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    leave_type_id uuid NOT NULL,
    year integer NOT NULL,
    entry_date date DEFAULT CURRENT_DATE NOT NULL,
    credit numeric(6,2) DEFAULT 0,
    debit numeric(6,2) DEFAULT 0,
    balance_after numeric(6,2),
    source text NOT NULL,
    reference_id uuid,
    remarks text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid
);


--
-- TOC entry 463 (class 1259 OID 30848)
-- Name: leave_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_policies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    leave_type_id uuid NOT NULL,
    policy_code text NOT NULL,
    name text NOT NULL,
    description text,
    entitlement_days numeric(6,2) DEFAULT 0 NOT NULL,
    accrual_method text DEFAULT 'annual'::text NOT NULL,
    accrual_rate_per_month numeric(6,3) DEFAULT NULL::numeric,
    prorate_on_join_exit boolean DEFAULT true,
    carry_forward_allowed boolean DEFAULT true,
    max_carry_forward_days integer DEFAULT 0,
    carry_forward_expiry_month integer,
    deduct_public_holidays boolean DEFAULT false,
    half_day_allowed boolean DEFAULT true,
    minimum_notice_days integer,
    max_consecutive_days integer,
    requires_approval boolean DEFAULT true NOT NULL,
    approval_flow jsonb DEFAULT '[{"role": "manager", "level": 1}, {"role": "hr", "level": 2}]'::jsonb,
    require_attachment boolean DEFAULT false,
    allow_negative_balance boolean DEFAULT false,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    valid_to date,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 464 (class 1259 OID 30926)
-- Name: leave_policy_group_map; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_policy_group_map (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    leave_policy_id uuid NOT NULL,
    policy_group_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 462 (class 1259 OID 30662)
-- Name: leave_policy_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_policy_groups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    description text,
    employment_type text,
    job_family text,
    job_role text,
    job_grade_min text,
    job_grade_max text,
    job_levels text[],
    org_unit_ids uuid[],
    work_location text,
    country_code text DEFAULT 'MY'::text,
    states text[],
    gender text,
    min_tenure_months integer,
    max_tenure_months integer,
    contract_months_min integer,
    contract_months_max integer,
    is_active boolean DEFAULT true NOT NULL,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    valid_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 468 (class 1259 OID 31252)
-- Name: leave_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    leave_type_id uuid NOT NULL,
    policy_id uuid,
    start_date date NOT NULL,
    end_date date NOT NULL,
    half_day boolean DEFAULT false NOT NULL,
    half_day_type text,
    days_requested numeric(6,2) DEFAULT 0 NOT NULL,
    reason text,
    attachment_url text,
    status text DEFAULT 'draft'::text NOT NULL,
    submitted_at timestamp with time zone,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT leave_requests_check CHECK ((((half_day = true) AND (half_day_type = ANY (ARRAY['am'::text, 'pm'::text]))) OR ((half_day = false) AND (half_day_type IS NULL)))),
    CONSTRAINT leave_requests_check1 CHECK ((end_date >= start_date)),
    CONSTRAINT leave_requests_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'approved'::text, 'partially_approved'::text, 'rejected'::text, 'cancelled'::text])))
);


--
-- TOC entry 399 (class 1259 OID 19514)
-- Name: leave_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name character varying(100) NOT NULL,
    code character varying(20) NOT NULL,
    description text,
    calculation_type character varying(50) DEFAULT 'fixed'::character varying,
    default_days numeric(5,2) DEFAULT 0,
    max_carry_forward numeric(5,2) DEFAULT 0,
    carry_forward_expiry_months integer,
    requires_approval boolean DEFAULT true,
    requires_attachment boolean DEFAULT false,
    requires_reason boolean DEFAULT true,
    min_notice_days integer DEFAULT 0,
    allow_half_day boolean DEFAULT true,
    allow_negative_balance boolean DEFAULT false,
    is_paid boolean DEFAULT true,
    affects_payroll boolean DEFAULT true,
    is_active boolean DEFAULT true,
    color character varying(20) DEFAULT '#10B981'::character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 438 (class 1259 OID 24044)
-- Name: overtime_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.overtime_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    overtime_date date NOT NULL,
    requested_hours numeric(5,2) NOT NULL,
    reason text,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    payroll_batch_id uuid
);


--
-- TOC entry 508 (class 1259 OID 37166)
-- Name: v_timesheet_daily; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_timesheet_daily AS
 WITH base AS (
         SELECT ar.company_id,
            ar.employee_id,
            ar.work_date,
            ar.clock_in_time,
            ar.clock_out_time,
            GREATEST(COALESCE((round((EXTRACT(epoch FROM (ar.clock_out_time - ar.clock_in_time)) / 60.0)))::integer, 0), 0) AS worked_minutes,
            ar.status,
            ar.created_at
           FROM public.attendance_records ar
        ), ot AS (
         SELECT orq.company_id,
            orq.employee_id,
            orq.overtime_date AS work_date,
            COALESCE(orq.requested_hours, (0)::numeric) AS requested_ot_hours
           FROM public.overtime_requests orq
          WHERE ((orq.status IS NULL) OR (orq.status = ANY (ARRAY['approved'::text, 'APPROVED'::text, 'approve'::text])))
        )
 SELECT b.company_id,
    b.employee_id,
    b.work_date,
    b.clock_in_time,
    b.clock_out_time,
    b.worked_minutes,
    round(((b.worked_minutes)::numeric / 60.0), 2) AS worked_hours,
    COALESCE(ot.requested_ot_hours, (0)::numeric) AS requested_ot_hours,
    b.status
   FROM (base b
     LEFT JOIN ot ON (((ot.company_id = b.company_id) AND (ot.employee_id = b.employee_id) AND (ot.work_date = b.work_date))));


--
-- TOC entry 509 (class 1259 OID 37212)
-- Name: v_timesheet_monthly; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_timesheet_monthly AS
 SELECT company_id,
    employee_id,
    (date_trunc('month'::text, (work_date)::timestamp with time zone))::date AS month_start,
    count(*) AS days_recorded,
    count(*) FILTER (WHERE (worked_minutes > 0)) AS days_worked,
    sum(worked_minutes) AS worked_minutes,
    round(((sum(worked_minutes))::numeric / 60.0), 2) AS worked_hours,
    COALESCE(sum(requested_ot_hours), (0)::numeric) AS requested_ot_hours
   FROM public.v_timesheet_daily d
  GROUP BY company_id, employee_id, ((date_trunc('month'::text, (work_date)::timestamp with time zone))::date);


--
-- TOC entry 510 (class 1259 OID 37258)
-- Name: mv_timesheet_monthly; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_timesheet_monthly AS
 SELECT company_id,
    employee_id,
    month_start,
    days_recorded,
    days_worked,
    worked_minutes,
    worked_hours,
    requested_ot_hours
   FROM public.v_timesheet_monthly
  WITH NO DATA;


--
-- TOC entry 416 (class 1259 OID 22338)
-- Name: notification_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_queue (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    channel text NOT NULL,
    recipient text NOT NULL,
    subject text,
    body text,
    payload_json jsonb,
    status text DEFAULT 'pending'::text NOT NULL,
    last_error text,
    retry_count integer DEFAULT 0 NOT NULL,
    scheduled_at timestamp with time zone DEFAULT now(),
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    priority smallint DEFAULT 1,
    template_code text,
    deleted_at timestamp with time zone,
    created_by uuid,
    updated_by uuid
);


--
-- TOC entry 6774 (class 0 OID 0)
-- Dependencies: 416
-- Name: COLUMN notification_queue.priority; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notification_queue.priority IS 'Higher = send earlier';


--
-- TOC entry 6775 (class 0 OID 0)
-- Dependencies: 416
-- Name: COLUMN notification_queue.template_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.notification_queue.template_code IS 'Message template identifier (e.g. PAYSLIP_READY_WHATSAPP)';


--
-- TOC entry 456 (class 1259 OID 29738)
-- Name: org_units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.org_units (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    description text,
    parent_id uuid,
    is_active boolean DEFAULT true NOT NULL,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    valid_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT org_units_code_check CHECK ((code ~ '^[A-Z0-9._-]{2,40}$'::text))
);


--
-- TOC entry 413 (class 1259 OID 22094)
-- Name: overtime_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.overtime_approvals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    ot_date date NOT NULL,
    requested_hours numeric(5,2),
    requested_reason text,
    status public.overtime_status_enum DEFAULT 'pending'::public.overtime_status_enum NOT NULL,
    approved_hours numeric(5,2),
    approver_id uuid,
    approval_notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    overtime_request_id uuid,
    approver_employee_id uuid,
    approval_status text NOT NULL,
    CONSTRAINT chk_ot_approval_status CHECK ((approval_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text, 'skipped'::text])))
);


--
-- TOC entry 6776 (class 0 OID 0)
-- Dependencies: 413
-- Name: COLUMN overtime_approvals.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.overtime_approvals.status IS 'LEGACY: replaced by approval_status; kept for backward compatibility';


--
-- TOC entry 6777 (class 0 OID 0)
-- Dependencies: 413
-- Name: COLUMN overtime_approvals.approver_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.overtime_approvals.approver_id IS 'LEGACY: replaced by approver_employee_id; kept for backward compatibility';


--
-- TOC entry 406 (class 1259 OID 19976)
-- Name: payroll_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_batches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    payroll_month date NOT NULL,
    pay_date date NOT NULL,
    cutoff_date date,
    total_employees integer DEFAULT 0 NOT NULL,
    total_gross_pay numeric(12,2) DEFAULT 0 NOT NULL,
    total_deductions numeric(12,2) DEFAULT 0 NOT NULL,
    total_net_pay numeric(12,2) DEFAULT 0 NOT NULL,
    total_employer_cost numeric(12,2) DEFAULT 0 NOT NULL,
    total_epf_employee numeric(12,2) DEFAULT 0,
    total_epf_employer numeric(12,2) DEFAULT 0,
    total_socso_employee numeric(12,2) DEFAULT 0,
    total_socso_employer numeric(12,2) DEFAULT 0,
    total_eis_employee numeric(12,2) DEFAULT 0,
    total_eis_employer numeric(12,2) DEFAULT 0,
    total_pcb numeric(12,2) DEFAULT 0,
    status character varying(20) DEFAULT 'draft'::character varying,
    approved_by uuid,
    approved_at timestamp with time zone,
    approval_notes text,
    payment_method character varying(50),
    payment_status character varying(20),
    payment_reference character varying(100),
    paid_at timestamp with time zone,
    is_locked boolean DEFAULT false,
    locked_at timestamp with time zone,
    locked_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 445 (class 1259 OID 27428)
-- Name: payroll_component_gl_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_component_gl_mappings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    component_code text NOT NULL,
    component_type text NOT NULL,
    debit_gl_account_id uuid NOT NULL,
    credit_gl_account_id uuid NOT NULL,
    cost_center_id uuid,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT payroll_component_gl_mappings_component_type_check CHECK ((component_type = ANY (ARRAY['earning'::text, 'deduction'::text, 'employer_contribution'::text])))
);


--
-- TOC entry 407 (class 1259 OID 20075)
-- Name: payroll_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payroll_batch_id uuid NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    employee_number character varying(50),
    employee_name character varying(200),
    department_name character varying(100),
    position_title character varying(100),
    working_days integer,
    days_worked numeric(5,2),
    unpaid_leave_days numeric(5,2) DEFAULT 0,
    basic_salary numeric(10,2) DEFAULT 0 NOT NULL,
    total_allowances numeric(10,2) DEFAULT 0,
    allowances jsonb,
    overtime_hours numeric(5,2) DEFAULT 0,
    overtime_pay numeric(10,2) DEFAULT 0,
    bonus numeric(10,2) DEFAULT 0,
    commission numeric(10,2) DEFAULT 0,
    incentives numeric(10,2) DEFAULT 0,
    claims_reimbursement numeric(10,2) DEFAULT 0,
    other_earnings numeric(10,2) DEFAULT 0,
    other_earnings_details jsonb,
    gross_pay numeric(10,2) DEFAULT 0 NOT NULL,
    epf_employee numeric(10,2) DEFAULT 0,
    epf_employer numeric(10,2) DEFAULT 0,
    epf_rate_employee numeric(5,4),
    epf_rate_employer numeric(5,4),
    socso_employee numeric(10,2) DEFAULT 0,
    socso_employer numeric(10,2) DEFAULT 0,
    eis_employee numeric(10,2) DEFAULT 0,
    eis_employer numeric(10,2) DEFAULT 0,
    pcb numeric(10,2) DEFAULT 0,
    pcb_category character varying(10),
    unpaid_leave_deduction numeric(10,2) DEFAULT 0,
    late_deduction numeric(10,2) DEFAULT 0,
    absence_deduction numeric(10,2) DEFAULT 0,
    loan_deduction numeric(10,2) DEFAULT 0,
    advance_salary_deduction numeric(10,2) DEFAULT 0,
    other_deductions numeric(10,2) DEFAULT 0,
    other_deductions_details jsonb,
    total_deductions numeric(10,2) DEFAULT 0 NOT NULL,
    net_pay numeric(10,2) DEFAULT 0 NOT NULL,
    employer_cost numeric(10,2) DEFAULT 0 NOT NULL,
    bank_name character varying(100),
    bank_account_number character varying(50),
    payment_method character varying(50) DEFAULT 'bank_transfer'::character varying,
    payment_status character varying(20) DEFAULT 'pending'::character varying,
    payment_reference character varying(100),
    paid_at timestamp with time zone,
    payslip_url character varying(500),
    payslip_sent_at timestamp with time zone,
    payslip_opened_at timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    created_by uuid,
    updated_by uuid,
    component_code text,
    amount numeric(14,2)
);


--
-- TOC entry 410 (class 1259 OID 20203)
-- Name: pcb_tax_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pcb_tax_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    monthly_income_from numeric(10,2) NOT NULL,
    monthly_income_to numeric(10,2) NOT NULL,
    with_zakat boolean DEFAULT false,
    monthly_tax numeric(10,2) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    created_by uuid,
    updated_by uuid,
    CONSTRAINT ck_pcb_income_range CHECK ((monthly_income_to >= monthly_income_from))
);


--
-- TOC entry 488 (class 1259 OID 34006)
-- Name: position_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.position_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    position_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    start_date date NOT NULL,
    end_date date,
    is_primary boolean DEFAULT true NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    fte numeric(4,2) DEFAULT 1.00 NOT NULL,
    grade_override text,
    cost_center_id uuid,
    assignment_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    CONSTRAINT chk_pos_assign_dates CHECK (((end_date IS NULL) OR (start_date <= end_date))),
    CONSTRAINT chk_pos_assign_fte CHECK (((fte > (0)::numeric) AND (fte <= 5.0))),
    CONSTRAINT chk_pos_assign_status CHECK ((status = ANY (ARRAY['active'::text, 'future'::text, 'ended'::text, 'cancelled'::text])))
);


--
-- TOC entry 6778 (class 0 OID 0)
-- Dependencies: 488
-- Name: TABLE position_assignments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.position_assignments IS 'Dated employee↔position links with primary flag; basis for headcount actuals, vacancies, transfers.';


--
-- TOC entry 491 (class 1259 OID 34218)
-- Name: position_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.position_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    action text NOT NULL,
    changed_at timestamp with time zone DEFAULT now() NOT NULL,
    changed_by uuid,
    reason text,
    old_row jsonb,
    new_row jsonb,
    CONSTRAINT chk_poshist_action CHECK ((action = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text])))
);


--
-- TOC entry 6779 (class 0 OID 0)
-- Dependencies: 491
-- Name: TABLE position_history; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.position_history IS 'Append-only audit of changes to positions and position_assignments.';


--
-- TOC entry 394 (class 1259 OID 18820)
-- Name: positions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.positions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    title character varying(100) NOT NULL,
    code character varying(20),
    department_id uuid,
    level character varying(50),
    description text,
    responsibilities text,
    requirements text,
    min_salary numeric(10,2),
    max_salary numeric(10,2),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    org_unit_id uuid,
    job_catalog_id uuid,
    position_title text,
    is_manager boolean DEFAULT false,
    fte numeric(4,2) DEFAULT 1.0,
    budgeted_headcount integer DEFAULT 1,
    filled_headcount integer DEFAULT 0,
    valid_from date DEFAULT CURRENT_DATE NOT NULL,
    valid_to date,
    grade text,
    cost_center_id uuid,
    fte_budget numeric(4,2) DEFAULT 1.0 NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    is_budgeted boolean DEFAULT true NOT NULL,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    role_band text DEFAULT 'staff'::text NOT NULL,
    CONSTRAINT chk_positions_fte CHECK (((fte_budget > (0)::numeric) AND (fte_budget <= 5.0))),
    CONSTRAINT chk_positions_role_band CHECK ((role_band = ANY (ARRAY['executive'::text, 'manager'::text, 'supervisor'::text, 'staff'::text]))),
    CONSTRAINT chk_positions_status CHECK ((status = ANY (ARRAY['open'::text, 'filled'::text, 'frozen'::text, 'closed'::text])))
);


--
-- TOC entry 405 (class 1259 OID 19910)
-- Name: public_holidays; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.public_holidays (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name character varying(200) NOT NULL,
    holiday_date date NOT NULL,
    applicable_states text[],
    holiday_type character varying(50) DEFAULT 'public_holiday'::character varying,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    deleted_at timestamp with time zone,
    updated_by uuid
);


--
-- TOC entry 422 (class 1259 OID 23244)
-- Name: rating_scale_values; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rating_scale_values (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    rating_scale_id uuid NOT NULL,
    value numeric(5,2) NOT NULL,
    label character varying(100) NOT NULL,
    description text,
    display_order integer NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 6780 (class 0 OID 0)
-- Dependencies: 422
-- Name: TABLE rating_scale_values; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.rating_scale_values IS 'Individual values/labels for rating scales';


--
-- TOC entry 421 (class 1259 OID 23213)
-- Name: rating_scales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rating_scales (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    scale_type public.rating_scale_type_enum DEFAULT 'numeric'::public.rating_scale_type_enum NOT NULL,
    min_value numeric(5,2),
    max_value numeric(5,2),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 6781 (class 0 OID 0)
-- Dependencies: 421
-- Name: TABLE rating_scales; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.rating_scales IS 'Rating scales used for appraisals';


--
-- TOC entry 440 (class 1259 OID 24331)
-- Name: shift_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    description text,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    break_minutes integer DEFAULT 60,
    requires_attendance boolean DEFAULT true NOT NULL,
    qualifies_overtime boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone,
    work_schedule_id uuid
);


--
-- TOC entry 409 (class 1259 OID 20191)
-- Name: socso_contribution_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.socso_contribution_rates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    wage_from numeric(10,2) NOT NULL,
    wage_to numeric(10,2) NOT NULL,
    employee_contribution numeric(10,2) NOT NULL,
    employer_contribution numeric(10,2) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    created_by uuid,
    updated_by uuid,
    CONSTRAINT ck_socso_wage_range CHECK ((wage_to >= wage_from))
);


--
-- TOC entry 388 (class 1259 OID 17474)
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    monthly_price numeric(10,2),
    annual_price numeric(10,2),
    max_employees integer,
    max_storage_mb integer,
    features jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 391 (class 1259 OID 17556)
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    token text NOT NULL,
    refresh_token text,
    ip_address inet,
    user_agent text,
    device_type character varying(50),
    expires_at timestamp with time zone NOT NULL,
    refresh_expires_at timestamp with time zone,
    is_active boolean DEFAULT true,
    revoked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_activity_at timestamp with time zone DEFAULT now() NOT NULL,
    company_id uuid NOT NULL
);


--
-- TOC entry 6782 (class 0 OID 0)
-- Dependencies: 391
-- Name: COLUMN user_sessions.company_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_sessions.company_id IS 'Tenant/company scope for RLS';


--
-- TOC entry 390 (class 1259 OID 17521)
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    employee_id uuid,
    email character varying(100) NOT NULL,
    password_hash text NOT NULL,
    role character varying(50) DEFAULT 'employee'::character varying NOT NULL,
    permissions jsonb DEFAULT '{}'::jsonb,
    mfa_enabled boolean DEFAULT false,
    mfa_secret character varying(200),
    is_active boolean DEFAULT true,
    is_email_verified boolean DEFAULT false,
    email_verified_at timestamp with time zone,
    last_login_at timestamp with time zone,
    last_login_ip inet,
    login_count integer DEFAULT 0,
    failed_login_attempts integer DEFAULT 0,
    locked_until timestamp with time zone,
    password_reset_token character varying(200),
    password_reset_expires timestamp with time zone,
    email_verification_token character varying(200),
    email_verification_expires timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid
);


--
-- TOC entry 493 (class 1259 OID 34364)
-- Name: v_active_assignments_today; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_active_assignments_today AS
 SELECT pa.id AS position_assignment_id,
    pa.company_id,
    pa.position_id,
    pa.employee_id,
    pa.is_primary,
    pa.fte,
    COALESCE(pa.cost_center_id, p.cost_center_id) AS cost_center_id,
    p.code AS position_code,
    p.title AS position_title,
    p.grade AS position_grade
   FROM (public.position_assignments pa
     JOIN public.positions p ON ((p.id = pa.position_id)))
  WHERE ((pa.deleted_at IS NULL) AND (p.deleted_at IS NULL) AND (pa.status = 'active'::text) AND (CURRENT_DATE >= pa.start_date) AND ((pa.end_date IS NULL) OR (CURRENT_DATE <= pa.end_date)));


--
-- TOC entry 6783 (class 0 OID 0)
-- Dependencies: 493
-- Name: VIEW v_active_assignments_today; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_active_assignments_today IS 'All active (by date) position assignments for CURRENT_DATE.';


--
-- TOC entry 486 (class 1259 OID 32927)
-- Name: v_active_kiosk_sessions; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_active_kiosk_sessions AS
 SELECT id,
    company_id,
    device_id,
    geo_location_id,
    session_label,
    started_at,
    expires_at,
    is_active,
    last_heartbeat_at,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at,
    ((expires_at IS NULL) OR (now() <= expires_at)) AS within_window
   FROM public.kiosk_sessions k
  WHERE ((is_active = true) AND (deleted_at IS NULL));


--
-- TOC entry 485 (class 1259 OID 32922)
-- Name: v_active_qr_tokens; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_active_qr_tokens AS
 SELECT id,
    company_id,
    geo_location_id,
    label,
    token,
    rotation_seconds,
    valid_from,
    valid_to,
    is_active,
    max_uses_per_token,
    notes,
    created_at,
    updated_at,
    created_by,
    updated_by,
    deleted_at,
    ((valid_to IS NULL) OR (now() <= valid_to)) AS within_window
   FROM public.attendance_qr_tokens t
  WHERE ((is_active = true) AND (deleted_at IS NULL));


--
-- TOC entry 506 (class 1259 OID 35843)
-- Name: v_employee_active_position; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_employee_active_position AS
 SELECT pa.company_id,
    pa.employee_id,
    pa.position_id,
    p.role_band
   FROM (public.position_assignments pa
     JOIN public.positions p ON ((p.id = pa.position_id)))
  WHERE ((pa.deleted_at IS NULL) AND (p.deleted_at IS NULL) AND (pa.status = 'active'::text) AND (CURRENT_DATE >= pa.start_date) AND ((pa.end_date IS NULL) OR (CURRENT_DATE <= pa.end_date)));


--
-- TOC entry 449 (class 1259 OID 28724)
-- Name: v_gl_journal_totals; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_gl_journal_totals AS
 SELECT h.id AS journal_id,
    h.company_id,
    (COALESCE(sum(
        CASE
            WHEN (l.debit_gl_account_id IS NOT NULL) THEN l.amount
            ELSE NULL::numeric
        END), (0)::numeric))::numeric(14,2) AS total_debit,
    (COALESCE(sum(
        CASE
            WHEN (l.credit_gl_account_id IS NOT NULL) THEN l.amount
            ELSE NULL::numeric
        END), (0)::numeric))::numeric(14,2) AS total_credit
   FROM (public.gl_journal_headers h
     LEFT JOIN public.gl_journal_lines l ON (((l.journal_id = h.id) AND (l.deleted_at IS NULL))))
  WHERE (h.deleted_at IS NULL)
  GROUP BY h.id, h.company_id;


--
-- TOC entry 490 (class 1259 OID 34172)
-- Name: v_headcount_plan_vs_actual; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_headcount_plan_vs_actual AS
 WITH pa AS (
         SELECT pa.company_id,
            COALESCE(pa.cost_center_id, p.cost_center_id) AS cc_id,
            pa.start_date,
            pa.end_date,
            pa.fte
           FROM (public.position_assignments pa
             JOIN public.positions p ON ((p.id = pa.position_id)))
          WHERE ((pa.deleted_at IS NULL) AND (p.deleted_at IS NULL))
        )
 SELECT id AS headcount_plan_id,
    company_id,
    cost_center_id,
    period_start,
    period_end,
    plan_fte,
    plan_cost,
    COALESCE(( SELECT COALESCE(sum(a.fte), (0)::numeric) AS "coalesce"
           FROM pa a
          WHERE ((a.company_id = hp.company_id) AND ((hp.cost_center_id IS NULL) OR (a.cc_id = hp.cost_center_id)) AND (daterange(a.start_date, COALESCE(a.end_date, 'infinity'::date), '[]'::text) && daterange(hp.period_start, hp.period_end, '[]'::text)))), (0)::numeric) AS actual_fte,
    (COALESCE(( SELECT COALESCE(sum(a.fte), (0)::numeric) AS "coalesce"
           FROM pa a
          WHERE ((a.company_id = hp.company_id) AND ((hp.cost_center_id IS NULL) OR (a.cc_id = hp.cost_center_id)) AND (daterange(a.start_date, COALESCE(a.end_date, 'infinity'::date), '[]'::text) && daterange(hp.period_start, hp.period_end, '[]'::text)))), (0)::numeric) - plan_fte) AS variance_fte
   FROM public.headcount_plans hp
  WHERE (deleted_at IS NULL);


--
-- TOC entry 494 (class 1259 OID 34410)
-- Name: v_headcount_summary_by_cc_today; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_headcount_summary_by_cc_today AS
 SELECT COALESCE(a.cost_center_id, p.cost_center_id) AS cost_center_id,
    p.company_id,
    count(*) FILTER (WHERE a.is_primary) AS primary_headcount,
    count(*) FILTER (WHERE (NOT a.is_primary)) AS secondary_headcount,
    sum(a.fte) AS total_fte
   FROM (public.position_assignments a
     JOIN public.positions p ON ((p.id = a.position_id)))
  WHERE ((a.deleted_at IS NULL) AND (p.deleted_at IS NULL) AND (a.status = 'active'::text) AND (CURRENT_DATE >= a.start_date) AND ((a.end_date IS NULL) OR (CURRENT_DATE <= a.end_date)))
  GROUP BY p.company_id, COALESCE(a.cost_center_id, p.cost_center_id);


--
-- TOC entry 6784 (class 0 OID 0)
-- Dependencies: 494
-- Name: VIEW v_headcount_summary_by_cc_today; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_headcount_summary_by_cc_today IS 'Today''s headcount (primary/secondary) and FTE by cost center.';


--
-- TOC entry 504 (class 1259 OID 35668)
-- Name: v_my_pending_actions; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_my_pending_actions AS
 SELECT 'overtime'::text AS action_type,
    o.id AS action_id,
    oa.id AS approval_id,
    oa.company_id,
    COALESCE(oa.approver_employee_id, oa.approver_id) AS approver_employee_id,
    NULL::integer AS level_no,
    COALESCE(oa.approval_status, (oa.status)::text) AS status,
    o.employee_id AS requester_employee_id,
    o.overtime_date AS action_date,
    COALESCE((o.requested_hours)::text, '-'::text) AS summary,
    o.created_at
   FROM (public.overtime_approvals oa
     JOIN public.overtime_requests o ON ((o.id = oa.overtime_request_id)))
  WHERE (COALESCE(oa.approval_status, (oa.status)::text) = 'pending'::text)
UNION ALL
 SELECT 'headcount_request'::text AS action_type,
    hr.id AS action_id,
    ha.id AS approval_id,
    ha.company_id,
    ha.approver_employee_id,
    ha.level_no,
    ha.status,
    hr.requester_employee_id,
    NULL::date AS action_date,
    COALESCE(hr.proposed_title, (( SELECT p.title
           FROM public.positions p
          WHERE (p.id = hr.position_id)))::text) AS summary,
    hr.created_at
   FROM (public.headcount_approvals ha
     JOIN public.headcount_requests hr ON ((hr.id = ha.headcount_request_id)))
  WHERE (ha.status = 'pending'::text)
UNION ALL
 SELECT 'requisition'::text AS action_type,
    jr.id AS action_id,
    jra.id AS approval_id,
    jra.company_id,
    jra.approver_employee_id,
    jra.level_no,
    jra.status,
    jr.requester_employee_id,
    (jr.opened_at)::date AS action_date,
    COALESCE(jr.proposed_title, (( SELECT p.title
           FROM public.positions p
          WHERE (p.id = jr.position_id)))::text) AS summary,
    jr.created_at
   FROM (public.job_requisition_approvals jra
     JOIN public.job_requisitions jr ON ((jr.id = jra.job_requisition_id)))
  WHERE (jra.status = 'pending'::text);


--
-- TOC entry 492 (class 1259 OID 34318)
-- Name: v_vacant_positions_today; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_vacant_positions_today AS
 SELECT p.id AS position_id,
    p.company_id,
    p.code,
    p.title,
    p.grade,
    p.cost_center_id,
    p.fte_budget,
    p.status
   FROM (public.positions p
     LEFT JOIN LATERAL ( SELECT 1 AS "?column?"
           FROM public.position_assignments pa
          WHERE ((pa.position_id = p.id) AND (pa.deleted_at IS NULL) AND (pa.status = 'active'::text) AND (CURRENT_DATE >= pa.start_date) AND ((pa.end_date IS NULL) OR (CURRENT_DATE <= pa.end_date)))
         LIMIT 1) has_active ON (true))
  WHERE ((p.deleted_at IS NULL) AND (p.status = ANY (ARRAY['open'::text, 'filled'::text])) AND (has_active.* IS NULL));


--
-- TOC entry 6785 (class 0 OID 0)
-- Dependencies: 492
-- Name: VIEW v_vacant_positions_today; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_vacant_positions_today IS 'Positions without an active assignment on CURRENT_DATE (open or filled status only).';


--
-- TOC entry 460 (class 1259 OID 30468)
-- Name: vw_employee_reporting_chain; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_employee_reporting_chain AS
 WITH RECURSIVE reporting AS (
         SELECT ja.company_id,
            ja.employee_id,
            ja.manager_id,
            0 AS level
           FROM public.employee_job_assignments ja
          WHERE (ja.manager_id IS NOT NULL)
        UNION ALL
         SELECT r.company_id,
            r.employee_id,
            ja.manager_id,
            (r.level + 1)
           FROM (reporting r
             JOIN public.employee_job_assignments ja ON (((r.manager_id = ja.employee_id) AND (r.company_id = ja.company_id))))
        )
 SELECT company_id,
    employee_id,
    manager_id,
    level
   FROM reporting;


--
-- TOC entry 472 (class 1259 OID 31512)
-- Name: vw_leave_approvals_expanded; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_leave_approvals_expanded AS
 SELECT a.company_id,
    a.request_id,
    a.level,
    a.approver_id,
    ae.first_name AS approver_first_name,
    ae.last_name AS approver_last_name,
    a.decision,
    a.decided_at,
    a.remarks,
    a.created_at,
    a.updated_at
   FROM (public.leave_approvals a
     JOIN public.employees ae ON ((ae.id = a.approver_id)))
  WHERE (a.deleted_at IS NULL);


--
-- TOC entry 471 (class 1259 OID 31464)
-- Name: vw_leave_requests_expanded; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_leave_requests_expanded AS
 SELECT r.company_id,
    r.id AS request_id,
    r.employee_id,
    e.first_name,
    e.last_name,
    e.email,
    r.leave_type_id,
    lt.code AS leave_type_code,
    lt.name AS leave_type_name,
    r.policy_id,
    r.start_date,
    r.end_date,
    r.half_day,
    r.half_day_type,
    r.days_requested,
    r.status,
    r.submitted_at,
    r.cancelled_at,
    r.attachment_url,
    r.reason,
    r.created_at,
    r.updated_at
   FROM ((public.leave_requests r
     JOIN public.employees e ON ((e.id = r.employee_id)))
     JOIN public.leave_types lt ON ((lt.id = r.leave_type_id)))
  WHERE (r.deleted_at IS NULL);


--
-- TOC entry 461 (class 1259 OID 30514)
-- Name: vw_open_positions; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_open_positions AS
 SELECT p.company_id,
    p.id AS position_id,
    ou.name AS department,
    p.position_title,
    jc.job_family,
    jc.job_role,
    (p.budgeted_headcount - p.filled_headcount) AS vacancies
   FROM ((public.positions p
     JOIN public.org_units ou ON ((p.org_unit_id = ou.id)))
     JOIN public.job_catalog jc ON ((p.job_catalog_id = jc.id)))
  WHERE ((p.deleted_at IS NULL) AND ((p.budgeted_headcount - p.filled_headcount) > 0));


--
-- TOC entry 459 (class 1259 OID 30422)
-- Name: vw_org_chart; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_org_chart AS
 SELECT ja.company_id,
    ou.name AS department,
    p.position_title,
    jc.job_family,
    jc.job_role,
    jc.job_grade,
    e.id AS employee_id,
    e.first_name,
    e.last_name,
    e.email,
    ja.manager_id AS manager_employee_id
   FROM ((((public.employee_job_assignments ja
     JOIN public.employees e ON ((ja.employee_id = e.id)))
     LEFT JOIN public.positions p ON ((ja.position_id = p.id)))
     LEFT JOIN public.job_catalog jc ON ((p.job_catalog_id = jc.id)))
     LEFT JOIN public.org_units ou ON ((p.org_unit_id = ou.id)))
  WHERE (ja.deleted_at IS NULL);


--
-- TOC entry 458 (class 1259 OID 30376)
-- Name: vw_position_directory; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_position_directory AS
 SELECT p.company_id,
    p.id AS position_id,
    p.position_title,
    jc.job_family,
    jc.job_role,
    jc.job_grade,
    ou.name AS org_unit_name,
    ou.id AS org_unit_id,
    p.budgeted_headcount,
    p.filled_headcount,
    (p.budgeted_headcount - p.filled_headcount) AS vacancies,
    p.is_manager,
    p.is_active,
    p.valid_from,
    p.valid_to,
    p.created_at,
    p.updated_at
   FROM ((public.positions p
     JOIN public.job_catalog jc ON ((p.job_catalog_id = jc.id)))
     JOIN public.org_units ou ON ((p.org_unit_id = ou.id)))
  WHERE (p.deleted_at IS NULL);


--
-- TOC entry 474 (class 1259 OID 31636)
-- Name: work_calendar_exceptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_calendar_exceptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    org_unit_id uuid,
    exception_date date NOT NULL,
    working_day boolean DEFAULT false NOT NULL,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 439 (class 1259 OID 24312)
-- Name: work_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_locations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    address_line_1 text,
    address_line_2 text,
    city text,
    state text,
    postcode text,
    country text DEFAULT 'MY'::text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 477 (class 1259 OID 31938)
-- Name: work_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    timezone character varying(50) DEFAULT 'Asia/Kuala_Lumpur'::character varying NOT NULL,
    mon_work boolean DEFAULT true,
    mon_start time without time zone,
    mon_end time without time zone,
    mon_break_mins integer DEFAULT 60,
    tue_work boolean DEFAULT true,
    tue_start time without time zone,
    tue_end time without time zone,
    tue_break_mins integer DEFAULT 60,
    wed_work boolean DEFAULT true,
    wed_start time without time zone,
    wed_end time without time zone,
    wed_break_mins integer DEFAULT 60,
    thu_work boolean DEFAULT true,
    thu_start time without time zone,
    thu_end time without time zone,
    thu_break_mins integer DEFAULT 60,
    fri_work boolean DEFAULT true,
    fri_start time without time zone,
    fri_end time without time zone,
    fri_break_mins integer DEFAULT 60,
    sat_work boolean DEFAULT false,
    sat_start time without time zone,
    sat_end time without time zone,
    sat_break_mins integer DEFAULT 60,
    sun_work boolean DEFAULT false,
    sun_start time without time zone,
    sun_end time without time zone,
    sun_break_mins integer DEFAULT 60,
    is_default boolean DEFAULT false,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 6786 (class 0 OID 0)
-- Dependencies: 477
-- Name: TABLE work_schedules; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.work_schedules IS 'Company weekly working pattern (used by shift templates, attendance, OT rules).';


--
-- TOC entry 437 (class 1259 OID 24032)
-- Name: zakat_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.zakat_rates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    income_from numeric(12,2) NOT NULL,
    income_to numeric(12,2) NOT NULL,
    rate_percent numeric(5,2),
    fixed_amount numeric(12,2),
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_to date,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    deleted_at timestamp with time zone
);


--
-- TOC entry 357 (class 1259 OID 16546)
-- Name: buckets; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    owner_id text,
    type storage.buckettype DEFAULT 'STANDARD'::storage.buckettype NOT NULL
);


--
-- TOC entry 6787 (class 0 OID 0)
-- Dependencies: 357
-- Name: COLUMN buckets.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.buckets.owner IS 'Field is deprecated, use owner_id instead';


--
-- TOC entry 387 (class 1259 OID 17420)
-- Name: buckets_analytics; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets_analytics (
    id text NOT NULL,
    type storage.buckettype DEFAULT 'ANALYTICS'::storage.buckettype NOT NULL,
    format text DEFAULT 'ICEBERG'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 359 (class 1259 OID 16588)
-- Name: migrations; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.migrations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hash character varying(40) NOT NULL,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 358 (class 1259 OID 16561)
-- Name: objects; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/'::text)) STORED,
    version text,
    owner_id text,
    user_metadata jsonb,
    level integer
);


--
-- TOC entry 6788 (class 0 OID 0)
-- Dependencies: 358
-- Name: COLUMN objects.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.objects.owner IS 'Field is deprecated, use owner_id instead';


--
-- TOC entry 386 (class 1259 OID 17370)
-- Name: prefixes; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.prefixes (
    bucket_id text NOT NULL,
    name text NOT NULL COLLATE pg_catalog."C",
    level integer GENERATED ALWAYS AS (storage.get_level(name)) STORED NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 383 (class 1259 OID 17305)
-- Name: s3_multipart_uploads; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads (
    id text NOT NULL,
    in_progress_size bigint DEFAULT 0 NOT NULL,
    upload_signature text NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    version text NOT NULL,
    owner_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_metadata jsonb
);


--
-- TOC entry 384 (class 1259 OID 17319)
-- Name: s3_multipart_uploads_parts; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads_parts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    upload_id text NOT NULL,
    size bigint DEFAULT 0 NOT NULL,
    part_number integer NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    etag text NOT NULL,
    owner_id text,
    version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- TOC entry 4706 (class 2604 OID 22998)
-- Name: db_meta id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.db_meta ALTER COLUMN id SET DEFAULT nextval('public.db_meta_id_seq'::regclass);


--
-- TOC entry 5509 (class 2606 OID 23597)
-- Name: appraisal_approvals appraisal_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_approvals
    ADD CONSTRAINT appraisal_approvals_pkey PRIMARY KEY (id);


--
-- TOC entry 5518 (class 2606 OID 23652)
-- Name: appraisal_comments appraisal_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_comments
    ADD CONSTRAINT appraisal_comments_pkey PRIMARY KEY (id);


--
-- TOC entry 5493 (class 2606 OID 23547)
-- Name: appraisal_competency_ratings appraisal_competency_ratings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_competency_ratings
    ADD CONSTRAINT appraisal_competency_ratings_pkey PRIMARY KEY (id);


--
-- TOC entry 5514 (class 2606 OID 23624)
-- Name: appraisal_documents appraisal_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_documents
    ADD CONSTRAINT appraisal_documents_pkey PRIMARY KEY (id);


--
-- TOC entry 5501 (class 2606 OID 23572)
-- Name: appraisal_goal_ratings appraisal_goal_ratings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_goal_ratings
    ADD CONSTRAINT appraisal_goal_ratings_pkey PRIMARY KEY (id);


--
-- TOC entry 5523 (class 2606 OID 23684)
-- Name: appraisal_history appraisal_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_history
    ADD CONSTRAINT appraisal_history_pkey PRIMARY KEY (id);


--
-- TOC entry 5420 (class 2606 OID 23192)
-- Name: appraisal_periods appraisal_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_periods
    ADD CONSTRAINT appraisal_periods_pkey PRIMARY KEY (id);


--
-- TOC entry 5485 (class 2606 OID 23516)
-- Name: appraisal_reviews appraisal_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_reviews
    ADD CONSTRAINT appraisal_reviews_pkey PRIMARY KEY (id);


--
-- TOC entry 5457 (class 2606 OID 23358)
-- Name: appraisal_template_competencies appraisal_template_competencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_template_competencies
    ADD CONSTRAINT appraisal_template_competencies_pkey PRIMARY KEY (id);


--
-- TOC entry 5440 (class 2606 OID 23278)
-- Name: appraisal_templates appraisal_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_templates
    ADD CONSTRAINT appraisal_templates_pkey PRIMARY KEY (id);


--
-- TOC entry 5465 (class 2606 OID 23384)
-- Name: appraisals appraisals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisals
    ADD CONSTRAINT appraisals_pkey PRIMARY KEY (id);


--
-- TOC entry 5778 (class 2606 OID 35578)
-- Name: approval_events approval_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_events
    ADD CONSTRAINT approval_events_pkey PRIMARY KEY (id);


--
-- TOC entry 5775 (class 2606 OID 35130)
-- Name: approval_function_tags approval_function_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_function_tags
    ADD CONSTRAINT approval_function_tags_pkey PRIMARY KEY (id);


--
-- TOC entry 5741 (class 2606 OID 34592)
-- Name: approval_policies approval_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_policies
    ADD CONSTRAINT approval_policies_pkey PRIMARY KEY (id);


--
-- TOC entry 5748 (class 2606 OID 34647)
-- Name: approval_policy_assignments approval_policy_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_policy_assignments
    ADD CONSTRAINT approval_policy_assignments_pkey PRIMARY KEY (id);


--
-- TOC entry 5745 (class 2606 OID 34617)
-- Name: approval_policy_levels approval_policy_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_policy_levels
    ADD CONSTRAINT approval_policy_levels_pkey PRIMARY KEY (id);


--
-- TOC entry 5696 (class 2606 OID 32623)
-- Name: attendance_exceptions attendance_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_exceptions
    ADD CONSTRAINT attendance_exceptions_pkey PRIMARY KEY (id);


--
-- TOC entry 5702 (class 2606 OID 32790)
-- Name: attendance_qr_tokens attendance_qr_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_qr_tokens
    ADD CONSTRAINT attendance_qr_tokens_pkey PRIMARY KEY (id);


--
-- TOC entry 5375 (class 2606 OID 22068)
-- Name: attendance_records attendance_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_pkey PRIMARY KEY (id);


--
-- TOC entry 5377 (class 2606 OID 22070)
-- Name: attendance_records attendance_records_unique_day; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_unique_day UNIQUE (company_id, employee_id, work_date);


--
-- TOC entry 5691 (class 2606 OID 32449)
-- Name: attendance_rules attendance_rules_company_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_rules
    ADD CONSTRAINT attendance_rules_company_id_key UNIQUE (company_id);


--
-- TOC entry 5693 (class 2606 OID 32447)
-- Name: attendance_rules attendance_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_rules
    ADD CONSTRAINT attendance_rules_pkey PRIMARY KEY (id);


--
-- TOC entry 5714 (class 2606 OID 33021)
-- Name: attendance_scan_logs attendance_scan_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_scan_logs
    ADD CONSTRAINT attendance_scan_logs_pkey PRIMARY KEY (id);


--
-- TOC entry 5209 (class 2606 OID 17583)
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- TOC entry 5395 (class 2606 OID 22187)
-- Name: claim_types claim_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_types
    ADD CONSTRAINT claim_types_pkey PRIMARY KEY (id);


--
-- TOC entry 5397 (class 2606 OID 22189)
-- Name: claim_types claim_types_unique_code_per_company; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_types
    ADD CONSTRAINT claim_types_unique_code_per_company UNIQUE (company_id, code);


--
-- TOC entry 5187 (class 2606 OID 17512)
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- TOC entry 5590 (class 2606 OID 27984)
-- Name: company_journal_sequences company_journal_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_journal_sequences
    ADD CONSTRAINT company_journal_sequences_pkey PRIMARY KEY (company_id);


--
-- TOC entry 5786 (class 2606 OID 36525)
-- Name: company_links company_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_links
    ADD CONSTRAINT company_links_pkey PRIMARY KEY (ancestor_id, descendant_id);


--
-- TOC entry 5412 (class 2606 OID 22373)
-- Name: company_notification_settings company_notification_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_notification_settings
    ADD CONSTRAINT company_notification_settings_pkey PRIMARY KEY (id);


--
-- TOC entry 5414 (class 2606 OID 22375)
-- Name: company_notification_settings company_notification_settings_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_notification_settings
    ADD CONSTRAINT company_notification_settings_unique UNIQUE (company_id, event_type);


--
-- TOC entry 5565 (class 2606 OID 26950)
-- Name: company_sequences company_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_sequences
    ADD CONSTRAINT company_sequences_pkey PRIMARY KEY (company_id);


--
-- TOC entry 5451 (class 2606 OID 23334)
-- Name: competencies competencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competencies
    ADD CONSTRAINT competencies_pkey PRIMARY KEY (id);


--
-- TOC entry 5446 (class 2606 OID 23314)
-- Name: competency_categories competency_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competency_categories
    ADD CONSTRAINT competency_categories_pkey PRIMARY KEY (id);


--
-- TOC entry 5557 (class 2606 OID 26721)
-- Name: cost_centers cost_centers_company_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_centers
    ADD CONSTRAINT cost_centers_company_id_code_key UNIQUE (company_id, code);


--
-- TOC entry 5559 (class 2606 OID 26719)
-- Name: cost_centers cost_centers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_centers
    ADD CONSTRAINT cost_centers_pkey PRIMARY KEY (id);


--
-- TOC entry 5418 (class 2606 OID 23003)
-- Name: db_meta db_meta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.db_meta
    ADD CONSTRAINT db_meta_pkey PRIMARY KEY (id);


--
-- TOC entry 5220 (class 2606 OID 18750)
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- TOC entry 5686 (class 2606 OID 32368)
-- Name: device_register device_register_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_register
    ADD CONSTRAINT device_register_pkey PRIMARY KEY (id);


--
-- TOC entry 5592 (class 2606 OID 29248)
-- Name: employee_actions employee_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_actions
    ADD CONSTRAINT employee_actions_pkey PRIMARY KEY (id);


--
-- TOC entry 5598 (class 2606 OID 29394)
-- Name: employee_addresses employee_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_addresses
    ADD CONSTRAINT employee_addresses_pkey PRIMARY KEY (id);


--
-- TOC entry 5265 (class 2606 OID 19050)
-- Name: employee_allowances employee_allowances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_allowances
    ADD CONSTRAINT employee_allowances_pkey PRIMARY KEY (id);


--
-- TOC entry 5608 (class 2606 OID 29619)
-- Name: employee_bank_accounts employee_bank_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_bank_accounts
    ADD CONSTRAINT employee_bank_accounts_pkey PRIMARY KEY (id);


--
-- TOC entry 5401 (class 2606 OID 22220)
-- Name: employee_claims employee_claims_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_claims
    ADD CONSTRAINT employee_claims_pkey PRIMARY KEY (id);


--
-- TOC entry 5605 (class 2606 OID 29535)
-- Name: employee_compensation employee_compensation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_compensation
    ADD CONSTRAINT employee_compensation_pkey PRIMARY KEY (id);


--
-- TOC entry 5272 (class 2606 OID 19154)
-- Name: employee_documents employee_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_pkey PRIMARY KEY (id);


--
-- TOC entry 5781 (class 2606 OID 35826)
-- Name: employee_function_memberships employee_function_memberships_company_id_employee_id_functi_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_function_memberships
    ADD CONSTRAINT employee_function_memberships_company_id_employee_id_functi_key UNIQUE (company_id, employee_id, function_tag_id);


--
-- TOC entry 5783 (class 2606 OID 35824)
-- Name: employee_function_memberships employee_function_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_function_memberships
    ADD CONSTRAINT employee_function_memberships_pkey PRIMARY KEY (id);


--
-- TOC entry 5474 (class 2606 OID 23446)
-- Name: employee_goals employee_goals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_pkey PRIMARY KEY (id);


--
-- TOC entry 5279 (class 2606 OID 19226)
-- Name: employee_history employee_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_pkey PRIMARY KEY (id);


--
-- TOC entry 5595 (class 2606 OID 29311)
-- Name: employee_job_assignments employee_job_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_job_assignments
    ADD CONSTRAINT employee_job_assignments_pkey PRIMARY KEY (id);


--
-- TOC entry 5636 (class 2606 OID 31026)
-- Name: employee_leave_entitlements employee_leave_entitlements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_leave_entitlements
    ADD CONSTRAINT employee_leave_entitlements_pkey PRIMARY KEY (id);


--
-- TOC entry 5370 (class 2606 OID 20229)
-- Name: employee_loans employee_loans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_loans
    ADD CONSTRAINT employee_loans_pkey PRIMARY KEY (id);


--
-- TOC entry 5550 (class 2606 OID 24362)
-- Name: employee_shift_assignments employee_shift_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_shift_assignments
    ADD CONSTRAINT employee_shift_assignments_pkey PRIMARY KEY (id);


--
-- TOC entry 5675 (class 2606 OID 32221)
-- Name: employee_shifts employee_shifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_shifts
    ADD CONSTRAINT employee_shifts_pkey PRIMARY KEY (id);


--
-- TOC entry 5601 (class 2606 OID 29464)
-- Name: employee_work_schedules employee_work_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_work_schedules
    ADD CONSTRAINT employee_work_schedules_pkey PRIMARY KEY (id);


--
-- TOC entry 5241 (class 2606 OID 18917)
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- TOC entry 5353 (class 2606 OID 20188)
-- Name: epf_rates epf_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.epf_rates
    ADD CONSTRAINT epf_rates_pkey PRIMARY KEY (id);


--
-- TOC entry 5682 (class 2606 OID 32304)
-- Name: geo_locations geo_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geo_locations
    ADD CONSTRAINT geo_locations_pkey PRIMARY KEY (id);


--
-- TOC entry 5567 (class 2606 OID 27369)
-- Name: gl_accounts gl_accounts_company_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_accounts
    ADD CONSTRAINT gl_accounts_company_id_code_key UNIQUE (company_id, code);


--
-- TOC entry 5569 (class 2606 OID 27367)
-- Name: gl_accounts gl_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_accounts
    ADD CONSTRAINT gl_accounts_pkey PRIMARY KEY (id);


--
-- TOC entry 5583 (class 2606 OID 27520)
-- Name: gl_journal_headers gl_journal_headers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_journal_headers
    ADD CONSTRAINT gl_journal_headers_pkey PRIMARY KEY (id);


--
-- TOC entry 5587 (class 2606 OID 27754)
-- Name: gl_journal_lines gl_journal_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_journal_lines
    ADD CONSTRAINT gl_journal_lines_pkey PRIMARY KEY (id);


--
-- TOC entry 5482 (class 2606 OID 23499)
-- Name: goal_milestones goal_milestones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goal_milestones
    ADD CONSTRAINT goal_milestones_pkey PRIMARY KEY (id);


--
-- TOC entry 5759 (class 2606 OID 34850)
-- Name: headcount_approvals headcount_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_approvals
    ADD CONSTRAINT headcount_approvals_pkey PRIMARY KEY (id);


--
-- TOC entry 5732 (class 2606 OID 34110)
-- Name: headcount_plans headcount_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_plans
    ADD CONSTRAINT headcount_plans_pkey PRIMARY KEY (id);


--
-- TOC entry 5752 (class 2606 OID 34760)
-- Name: headcount_requests headcount_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_requests
    ADD CONSTRAINT headcount_requests_pkey PRIMARY KEY (id);


--
-- TOC entry 5656 (class 2606 OID 31589)
-- Name: holiday_calendar holiday_calendar_company_id_country_code_state_holiday_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holiday_calendar
    ADD CONSTRAINT holiday_calendar_company_id_country_code_state_holiday_date_key UNIQUE (company_id, country_code, state, holiday_date);


--
-- TOC entry 5658 (class 2606 OID 31587)
-- Name: holiday_calendar holiday_calendar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holiday_calendar
    ADD CONSTRAINT holiday_calendar_pkey PRIMARY KEY (id);


--
-- TOC entry 5620 (class 2606 OID 29819)
-- Name: job_catalog job_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_catalog
    ADD CONSTRAINT job_catalog_pkey PRIMARY KEY (id);


--
-- TOC entry 5772 (class 2606 OID 35020)
-- Name: job_requisition_approvals job_requisition_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisition_approvals
    ADD CONSTRAINT job_requisition_approvals_pkey PRIMARY KEY (id);


--
-- TOC entry 5769 (class 2606 OID 34919)
-- Name: job_requisitions job_requisitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisitions
    ADD CONSTRAINT job_requisitions_pkey PRIMARY KEY (id);


--
-- TOC entry 5712 (class 2606 OID 32859)
-- Name: kiosk_sessions kiosk_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kiosk_sessions
    ADD CONSTRAINT kiosk_sessions_pkey PRIMARY KEY (id);


--
-- TOC entry 5668 (class 2606 OID 31794)
-- Name: leave_accrual_log leave_accrual_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_accrual_log
    ADD CONSTRAINT leave_accrual_log_pkey PRIMARY KEY (id);


--
-- TOC entry 5665 (class 2606 OID 31734)
-- Name: leave_accrual_runs leave_accrual_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_accrual_runs
    ADD CONSTRAINT leave_accrual_runs_pkey PRIMARY KEY (id);


--
-- TOC entry 5312 (class 2606 OID 19691)
-- Name: leave_applications leave_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_pkey PRIMARY KEY (id);


--
-- TOC entry 5318 (class 2606 OID 19752)
-- Name: leave_approval_history leave_approval_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approval_history
    ADD CONSTRAINT leave_approval_history_pkey PRIMARY KEY (id);


--
-- TOC entry 5649 (class 2606 OID 31341)
-- Name: leave_approvals leave_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approvals
    ADD CONSTRAINT leave_approvals_pkey PRIMARY KEY (id);


--
-- TOC entry 5651 (class 2606 OID 31343)
-- Name: leave_approvals leave_approvals_request_id_level_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approvals
    ADD CONSTRAINT leave_approvals_request_id_level_key UNIQUE (request_id, level);


--
-- TOC entry 5328 (class 2606 OID 19799)
-- Name: leave_balance_adjustments leave_balance_adjustments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balance_adjustments
    ADD CONSTRAINT leave_balance_adjustments_pkey PRIMARY KEY (id);


--
-- TOC entry 5639 (class 2606 OID 31104)
-- Name: leave_balances leave_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_pkey PRIMARY KEY (id);


--
-- TOC entry 5323 (class 2606 OID 19777)
-- Name: leave_blackout_periods leave_blackout_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_blackout_periods
    ADD CONSTRAINT leave_blackout_periods_pkey PRIMARY KEY (id);


--
-- TOC entry 5654 (class 2606 OID 31411)
-- Name: leave_cancel_history leave_cancel_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_cancel_history
    ADD CONSTRAINT leave_cancel_history_pkey PRIMARY KEY (id);


--
-- TOC entry 5298 (class 2606 OID 19612)
-- Name: leave_entitlements leave_entitlements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_entitlements
    ADD CONSTRAINT leave_entitlements_pkey PRIMARY KEY (id);


--
-- TOC entry 5643 (class 2606 OID 31173)
-- Name: leave_ledger leave_ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_ledger
    ADD CONSTRAINT leave_ledger_pkey PRIMARY KEY (id);


--
-- TOC entry 5628 (class 2606 OID 30871)
-- Name: leave_policies leave_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_policies
    ADD CONSTRAINT leave_policies_pkey PRIMARY KEY (id);


--
-- TOC entry 5632 (class 2606 OID 30934)
-- Name: leave_policy_group_map leave_policy_group_map_company_id_leave_policy_id_policy_gr_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_policy_group_map
    ADD CONSTRAINT leave_policy_group_map_company_id_leave_policy_id_policy_gr_key UNIQUE (company_id, leave_policy_id, policy_group_id);


--
-- TOC entry 5634 (class 2606 OID 30932)
-- Name: leave_policy_group_map leave_policy_group_map_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_policy_group_map
    ADD CONSTRAINT leave_policy_group_map_pkey PRIMARY KEY (id);


--
-- TOC entry 5624 (class 2606 OID 30674)
-- Name: leave_policy_groups leave_policy_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_policy_groups
    ADD CONSTRAINT leave_policy_groups_pkey PRIMARY KEY (id);


--
-- TOC entry 5646 (class 2606 OID 31267)
-- Name: leave_requests leave_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_pkey PRIMARY KEY (id);


--
-- TOC entry 5287 (class 2606 OID 19536)
-- Name: leave_types leave_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT leave_types_pkey PRIMARY KEY (id);


--
-- TOC entry 5410 (class 2606 OID 22350)
-- Name: notification_queue notification_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_queue
    ADD CONSTRAINT notification_queue_pkey PRIMARY KEY (id);


--
-- TOC entry 5613 (class 2606 OID 29752)
-- Name: org_units org_units_company_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_units
    ADD CONSTRAINT org_units_company_id_code_key UNIQUE (company_id, code);


--
-- TOC entry 5615 (class 2606 OID 29750)
-- Name: org_units org_units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_units
    ADD CONSTRAINT org_units_pkey PRIMARY KEY (id);


--
-- TOC entry 5393 (class 2606 OID 22105)
-- Name: overtime_approvals overtime_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_approvals
    ADD CONSTRAINT overtime_approvals_pkey PRIMARY KEY (id);


--
-- TOC entry 5538 (class 2606 OID 24054)
-- Name: overtime_requests overtime_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_requests
    ADD CONSTRAINT overtime_requests_pkey PRIMARY KEY (id);


--
-- TOC entry 5340 (class 2606 OID 19999)
-- Name: payroll_batches payroll_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_batches
    ADD CONSTRAINT payroll_batches_pkey PRIMARY KEY (id);


--
-- TOC entry 5578 (class 2606 OID 27439)
-- Name: payroll_component_gl_mappings payroll_component_gl_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_component_gl_mappings
    ADD CONSTRAINT payroll_component_gl_mappings_pkey PRIMARY KEY (id);


--
-- TOC entry 5349 (class 2606 OID 20113)
-- Name: payroll_items payroll_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_items
    ADD CONSTRAINT payroll_items_pkey PRIMARY KEY (id);


--
-- TOC entry 5368 (class 2606 OID 20212)
-- Name: pcb_tax_schedules pcb_tax_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcb_tax_schedules
    ADD CONSTRAINT pcb_tax_schedules_pkey PRIMARY KEY (id);


--
-- TOC entry 5729 (class 2606 OID 34018)
-- Name: position_assignments position_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.position_assignments
    ADD CONSTRAINT position_assignments_pkey PRIMARY KEY (id);


--
-- TOC entry 5739 (class 2606 OID 34226)
-- Name: position_history position_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.position_history
    ADD CONSTRAINT position_history_pkey PRIMARY KEY (id);


--
-- TOC entry 5235 (class 2606 OID 18830)
-- Name: positions positions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_pkey PRIMARY KEY (id);


--
-- TOC entry 5333 (class 2606 OID 19920)
-- Name: public_holidays public_holidays_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_holidays
    ADD CONSTRAINT public_holidays_pkey PRIMARY KEY (id);


--
-- TOC entry 5434 (class 2606 OID 23253)
-- Name: rating_scale_values rating_scale_values_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rating_scale_values
    ADD CONSTRAINT rating_scale_values_pkey PRIMARY KEY (id);


--
-- TOC entry 5429 (class 2606 OID 23224)
-- Name: rating_scales rating_scales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rating_scales
    ADD CONSTRAINT rating_scales_pkey PRIMARY KEY (id);


--
-- TOC entry 5548 (class 2606 OID 24344)
-- Name: shift_templates shift_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_templates
    ADD CONSTRAINT shift_templates_pkey PRIMARY KEY (id);


--
-- TOC entry 5362 (class 2606 OID 20199)
-- Name: socso_contribution_rates socso_contribution_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.socso_contribution_rates
    ADD CONSTRAINT socso_contribution_rates_pkey PRIMARY KEY (id);


--
-- TOC entry 5183 (class 2606 OID 17486)
-- Name: subscription_plans subscription_plans_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_code_key UNIQUE (code);


--
-- TOC entry 5185 (class 2606 OID 17484)
-- Name: subscription_plans subscription_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_pkey PRIMARY KEY (id);


--
-- TOC entry 5425 (class 2606 OID 23194)
-- Name: appraisal_periods unique_appraisal_period_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_periods
    ADD CONSTRAINT unique_appraisal_period_name UNIQUE (company_id, name, deleted_at);


--
-- TOC entry 5491 (class 2606 OID 23518)
-- Name: appraisal_reviews unique_appraisal_reviewer_type; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_reviews
    ADD CONSTRAINT unique_appraisal_reviewer_type UNIQUE (appraisal_id, reviewer_id, review_type);


--
-- TOC entry 5444 (class 2606 OID 23280)
-- Name: appraisal_templates unique_appraisal_template_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_templates
    ADD CONSTRAINT unique_appraisal_template_name UNIQUE (company_id, name, deleted_at);


--
-- TOC entry 5449 (class 2606 OID 23316)
-- Name: competency_categories unique_competency_category_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competency_categories
    ADD CONSTRAINT unique_competency_category_name UNIQUE (company_id, name, deleted_at);


--
-- TOC entry 5455 (class 2606 OID 23336)
-- Name: competencies unique_competency_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competencies
    ADD CONSTRAINT unique_competency_name UNIQUE (company_id, name, deleted_at);


--
-- TOC entry 5472 (class 2606 OID 23386)
-- Name: appraisals unique_employee_period; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisals
    ADD CONSTRAINT unique_employee_period UNIQUE (employee_id, period_id, deleted_at);


--
-- TOC entry 5431 (class 2606 OID 23226)
-- Name: rating_scales unique_rating_scale_name; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rating_scales
    ADD CONSTRAINT unique_rating_scale_name UNIQUE (company_id, name, deleted_at);


--
-- TOC entry 5499 (class 2606 OID 23549)
-- Name: appraisal_competency_ratings unique_review_competency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_competency_ratings
    ADD CONSTRAINT unique_review_competency UNIQUE (review_id, competency_id);


--
-- TOC entry 5507 (class 2606 OID 23574)
-- Name: appraisal_goal_ratings unique_review_goal; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_goal_ratings
    ADD CONSTRAINT unique_review_goal UNIQUE (review_id, goal_id);


--
-- TOC entry 5436 (class 2606 OID 23257)
-- Name: rating_scale_values unique_scale_order; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rating_scale_values
    ADD CONSTRAINT unique_scale_order UNIQUE (rating_scale_id, display_order);


--
-- TOC entry 5438 (class 2606 OID 23255)
-- Name: rating_scale_values unique_scale_value; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rating_scale_values
    ADD CONSTRAINT unique_scale_value UNIQUE (rating_scale_id, value);


--
-- TOC entry 5463 (class 2606 OID 23360)
-- Name: appraisal_template_competencies unique_template_competency; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_template_competencies
    ADD CONSTRAINT unique_template_competency UNIQUE (template_id, competency_id);


--
-- TOC entry 5270 (class 2606 OID 19052)
-- Name: employee_allowances uq_allowance_per_period; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_allowances
    ADD CONSTRAINT uq_allowance_per_period UNIQUE (employee_id, allowance_name, effective_from);


--
-- TOC entry 5342 (class 2606 OID 20001)
-- Name: payroll_batches uq_company_payroll_month; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_batches
    ADD CONSTRAINT uq_company_payroll_month UNIQUE (company_id, payroll_month);


--
-- TOC entry 5227 (class 2606 OID 18752)
-- Name: departments uq_department_code; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT uq_department_code UNIQUE (company_id, code);


--
-- TOC entry 5258 (class 2606 OID 18921)
-- Name: employees uq_employee_ic; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT uq_employee_ic UNIQUE (company_id, ic_number);


--
-- TOC entry 5260 (class 2606 OID 18919)
-- Name: employees uq_employee_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT uq_employee_number UNIQUE (company_id, employee_number);


--
-- TOC entry 5300 (class 2606 OID 19614)
-- Name: leave_entitlements uq_entitlement; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_entitlements
    ADD CONSTRAINT uq_entitlement UNIQUE (employee_id, leave_type_id, year);


--
-- TOC entry 5573 (class 2606 OID 28519)
-- Name: gl_accounts uq_gl_accounts_company_code; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_accounts
    ADD CONSTRAINT uq_gl_accounts_company_code UNIQUE (company_id, code);


--
-- TOC entry 5289 (class 2606 OID 19538)
-- Name: leave_types uq_leave_type_code; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT uq_leave_type_code UNIQUE (company_id, code);


--
-- TOC entry 5581 (class 2606 OID 28581)
-- Name: payroll_component_gl_mappings uq_payroll_component_gl_mappings_company_component; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_component_gl_mappings
    ADD CONSTRAINT uq_payroll_component_gl_mappings_company_component UNIQUE (company_id, component_code);


--
-- TOC entry 5351 (class 2606 OID 20115)
-- Name: payroll_items uq_payroll_item; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_items
    ADD CONSTRAINT uq_payroll_item UNIQUE (payroll_batch_id, employee_id);


--
-- TOC entry 5238 (class 2606 OID 30167)
-- Name: positions uq_positions_company_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT uq_positions_company_id_id UNIQUE (company_id, id);


--
-- TOC entry 5198 (class 2606 OID 17539)
-- Name: users uq_users_company_email; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT uq_users_company_email UNIQUE (company_id, email);


--
-- TOC entry 5207 (class 2606 OID 17566)
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (id);


--
-- TOC entry 5200 (class 2606 OID 17537)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 5660 (class 2606 OID 31647)
-- Name: work_calendar_exceptions work_calendar_exceptions_company_id_org_unit_id_exception_d_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_calendar_exceptions
    ADD CONSTRAINT work_calendar_exceptions_company_id_org_unit_id_exception_d_key UNIQUE (company_id, org_unit_id, exception_date);


--
-- TOC entry 5662 (class 2606 OID 31645)
-- Name: work_calendar_exceptions work_calendar_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_calendar_exceptions
    ADD CONSTRAINT work_calendar_exceptions_pkey PRIMARY KEY (id);


--
-- TOC entry 5543 (class 2606 OID 24323)
-- Name: work_locations work_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_locations
    ADD CONSTRAINT work_locations_pkey PRIMARY KEY (id);


--
-- TOC entry 5673 (class 2606 OID 31964)
-- Name: work_schedules work_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_pkey PRIMARY KEY (id);


--
-- TOC entry 5530 (class 2606 OID 24041)
-- Name: zakat_rates zakat_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zakat_rates
    ADD CONSTRAINT zakat_rates_pkey PRIMARY KEY (id);


--
-- TOC entry 5180 (class 2606 OID 17430)
-- Name: buckets_analytics buckets_analytics_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets_analytics
    ADD CONSTRAINT buckets_analytics_pkey PRIMARY KEY (id);


--
-- TOC entry 5158 (class 2606 OID 16554)
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- TOC entry 5168 (class 2606 OID 16595)
-- Name: migrations migrations_name_key; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_name_key UNIQUE (name);


--
-- TOC entry 5170 (class 2606 OID 16593)
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- TOC entry 5166 (class 2606 OID 16571)
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- TOC entry 5178 (class 2606 OID 17379)
-- Name: prefixes prefixes_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.prefixes
    ADD CONSTRAINT prefixes_pkey PRIMARY KEY (bucket_id, level, name);


--
-- TOC entry 5175 (class 2606 OID 17328)
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_pkey PRIMARY KEY (id);


--
-- TOC entry 5173 (class 2606 OID 17313)
-- Name: s3_multipart_uploads s3_multipart_uploads_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_pkey PRIMARY KEY (id);


--
-- TOC entry 5722 (class 1259 OID 34047)
-- Name: ex_pos_assign_emp_overlap; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ex_pos_assign_emp_overlap ON public.position_assignments USING gist (employee_id, daterange(start_date, COALESCE(end_date, 'infinity'::date), '[]'::text)) WHERE (deleted_at IS NULL);


--
-- TOC entry 5494 (class 1259 OID 36080)
-- Name: idx_acr_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_acr_company_created ON public.appraisal_competency_ratings USING btree (company_id, created_at);


--
-- TOC entry 5502 (class 1259 OID 36081)
-- Name: idx_agr_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agr_company_created ON public.appraisal_goal_ratings USING btree (company_id, created_at);


--
-- TOC entry 5749 (class 1259 OID 34659)
-- Name: idx_ap_assign_company_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ap_assign_company_action ON public.approval_policy_assignments USING btree (company_id, action_type);


--
-- TOC entry 5742 (class 1259 OID 34600)
-- Name: idx_ap_policies_company_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ap_policies_company_action ON public.approval_policies USING btree (company_id, action_type);


--
-- TOC entry 5779 (class 1259 OID 35579)
-- Name: idx_appr_events_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appr_events_company ON public.approval_events USING btree (company_id, action_type, decided_at DESC);


--
-- TOC entry 5510 (class 1259 OID 23613)
-- Name: idx_appraisal_approvals_appraisal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_approvals_appraisal ON public.appraisal_approvals USING btree (appraisal_id);


--
-- TOC entry 5511 (class 1259 OID 23614)
-- Name: idx_appraisal_approvals_approver; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_approvals_approver ON public.appraisal_approvals USING btree (approver_id);


--
-- TOC entry 5512 (class 1259 OID 23615)
-- Name: idx_appraisal_approvals_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_approvals_status ON public.appraisal_approvals USING btree (appraisal_id, status);


--
-- TOC entry 5519 (class 1259 OID 23673)
-- Name: idx_appraisal_comments_appraisal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_comments_appraisal ON public.appraisal_comments USING btree (appraisal_id);


--
-- TOC entry 5520 (class 1259 OID 23675)
-- Name: idx_appraisal_comments_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_comments_parent ON public.appraisal_comments USING btree (parent_comment_id);


--
-- TOC entry 5521 (class 1259 OID 23674)
-- Name: idx_appraisal_comments_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_comments_user ON public.appraisal_comments USING btree (user_id);


--
-- TOC entry 5495 (class 1259 OID 36014)
-- Name: idx_appraisal_competency_ratings_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_competency_ratings_company_id ON public.appraisal_competency_ratings USING btree (company_id);


--
-- TOC entry 5515 (class 1259 OID 23640)
-- Name: idx_appraisal_documents_appraisal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_documents_appraisal ON public.appraisal_documents USING btree (appraisal_id);


--
-- TOC entry 5516 (class 1259 OID 23641)
-- Name: idx_appraisal_documents_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_documents_company ON public.appraisal_documents USING btree (company_id);


--
-- TOC entry 5503 (class 1259 OID 36015)
-- Name: idx_appraisal_goal_ratings_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_goal_ratings_company_id ON public.appraisal_goal_ratings USING btree (company_id);


--
-- TOC entry 5524 (class 1259 OID 23700)
-- Name: idx_appraisal_history_appraisal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_history_appraisal ON public.appraisal_history USING btree (appraisal_id);


--
-- TOC entry 5525 (class 1259 OID 23701)
-- Name: idx_appraisal_history_changed_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_history_changed_by ON public.appraisal_history USING btree (changed_by);


--
-- TOC entry 5526 (class 1259 OID 23702)
-- Name: idx_appraisal_history_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_history_date ON public.appraisal_history USING btree (created_at);


--
-- TOC entry 5421 (class 1259 OID 23211)
-- Name: idx_appraisal_periods_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_periods_active ON public.appraisal_periods USING btree (company_id, is_active) WHERE (deleted_at IS NULL);


--
-- TOC entry 5422 (class 1259 OID 23210)
-- Name: idx_appraisal_periods_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_periods_company ON public.appraisal_periods USING btree (company_id);


--
-- TOC entry 5423 (class 1259 OID 23212)
-- Name: idx_appraisal_periods_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_periods_dates ON public.appraisal_periods USING btree (start_date, end_date);


--
-- TOC entry 5486 (class 1259 OID 23535)
-- Name: idx_appraisal_reviews_appraisal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_reviews_appraisal ON public.appraisal_reviews USING btree (appraisal_id);


--
-- TOC entry 5487 (class 1259 OID 23534)
-- Name: idx_appraisal_reviews_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_reviews_company ON public.appraisal_reviews USING btree (company_id);


--
-- TOC entry 5488 (class 1259 OID 23536)
-- Name: idx_appraisal_reviews_reviewer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_reviews_reviewer ON public.appraisal_reviews USING btree (reviewer_id);


--
-- TOC entry 5489 (class 1259 OID 23537)
-- Name: idx_appraisal_reviews_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_reviews_type ON public.appraisal_reviews USING btree (appraisal_id, review_type);


--
-- TOC entry 5458 (class 1259 OID 36016)
-- Name: idx_appraisal_template_competencies_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_template_competencies_company_id ON public.appraisal_template_competencies USING btree (company_id);


--
-- TOC entry 5441 (class 1259 OID 23302)
-- Name: idx_appraisal_templates_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_templates_active ON public.appraisal_templates USING btree (company_id, is_active) WHERE (deleted_at IS NULL);


--
-- TOC entry 5442 (class 1259 OID 23301)
-- Name: idx_appraisal_templates_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisal_templates_company ON public.appraisal_templates USING btree (company_id);


--
-- TOC entry 5466 (class 1259 OID 23427)
-- Name: idx_appraisals_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisals_company ON public.appraisals USING btree (company_id);


--
-- TOC entry 5467 (class 1259 OID 23428)
-- Name: idx_appraisals_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisals_employee ON public.appraisals USING btree (employee_id);


--
-- TOC entry 5468 (class 1259 OID 23429)
-- Name: idx_appraisals_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisals_period ON public.appraisals USING btree (period_id);


--
-- TOC entry 5469 (class 1259 OID 23430)
-- Name: idx_appraisals_reviewer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisals_reviewer ON public.appraisals USING btree (reviewer_id);


--
-- TOC entry 5470 (class 1259 OID 23431)
-- Name: idx_appraisals_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appraisals_status ON public.appraisals USING btree (company_id, status) WHERE (deleted_at IS NULL);


--
-- TOC entry 5551 (class 1259 OID 24384)
-- Name: idx_assign_company_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assign_company_date ON public.employee_shift_assignments USING btree (company_id, work_date DESC);


--
-- TOC entry 5552 (class 1259 OID 24385)
-- Name: idx_assign_company_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assign_company_status ON public.employee_shift_assignments USING btree (company_id, status) WHERE (deleted_at IS NULL);


--
-- TOC entry 5553 (class 1259 OID 24386)
-- Name: idx_assign_employee_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assign_employee_date ON public.employee_shift_assignments USING btree (employee_id, work_date DESC);


--
-- TOC entry 5554 (class 1259 OID 24383)
-- Name: idx_assign_unique_emp_day; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_assign_unique_emp_day ON public.employee_shift_assignments USING btree (employee_id, work_date) WHERE (deleted_at IS NULL);


--
-- TOC entry 5459 (class 1259 OID 36082)
-- Name: idx_atc_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_atc_company_created ON public.appraisal_template_competencies USING btree (company_id, created_at);


--
-- TOC entry 5378 (class 1259 OID 22091)
-- Name: idx_attendance_company_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_company_date ON public.attendance_records USING btree (company_id, work_date DESC);


--
-- TOC entry 5379 (class 1259 OID 22092)
-- Name: idx_attendance_employee_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_employee_date ON public.attendance_records USING btree (employee_id, work_date DESC);


--
-- TOC entry 5697 (class 1259 OID 37097)
-- Name: idx_attendance_exceptions_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_exceptions_company_created ON public.attendance_exceptions USING btree (company_id, created_at);


--
-- TOC entry 5380 (class 1259 OID 32561)
-- Name: idx_attendance_geo_device; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_geo_device ON public.attendance_records USING btree (geo_location_id, device_id);


--
-- TOC entry 5703 (class 1259 OID 37098)
-- Name: idx_attendance_qr_tokens_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_qr_tokens_company_created ON public.attendance_qr_tokens USING btree (company_id, created_at);


--
-- TOC entry 5381 (class 1259 OID 37094)
-- Name: idx_attendance_records_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_records_company_created ON public.attendance_records USING btree (company_id, created_at);


--
-- TOC entry 5694 (class 1259 OID 37096)
-- Name: idx_attendance_rules_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_rules_company_created ON public.attendance_rules USING btree (company_id, created_at);


--
-- TOC entry 5715 (class 1259 OID 37095)
-- Name: idx_attendance_scan_logs_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_scan_logs_company_created ON public.attendance_scan_logs USING btree (company_id, created_at);


--
-- TOC entry 5382 (class 1259 OID 32560)
-- Name: idx_attendance_shift_assignment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_shift_assignment ON public.attendance_records USING btree (shift_assignment_id);


--
-- TOC entry 5383 (class 1259 OID 22093)
-- Name: idx_attendance_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_status ON public.attendance_records USING btree (status);


--
-- TOC entry 5384 (class 1259 OID 22894)
-- Name: idx_attendance_work_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_work_date ON public.attendance_records USING btree (work_date);


--
-- TOC entry 5698 (class 1259 OID 32639)
-- Name: idx_attn_exc_company_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attn_exc_company_date ON public.attendance_exceptions USING btree (company_id, work_date);


--
-- TOC entry 5699 (class 1259 OID 32640)
-- Name: idx_attn_exc_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attn_exc_employee ON public.attendance_exceptions USING btree (employee_id);


--
-- TOC entry 5700 (class 1259 OID 32641)
-- Name: idx_attn_exc_record; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attn_exc_record ON public.attendance_exceptions USING btree (attendance_record_id);


--
-- TOC entry 5385 (class 1259 OID 37105)
-- Name: idx_attrec_company_emp_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attrec_company_emp_date ON public.attendance_records USING btree (company_id, employee_id, work_date);


--
-- TOC entry 5210 (class 1259 OID 17597)
-- Name: idx_audit_logs_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_action ON public.audit_logs USING btree (action);


--
-- TOC entry 5211 (class 1259 OID 21997)
-- Name: idx_audit_logs_action_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_action_created ON public.audit_logs USING btree (action, created_at DESC);


--
-- TOC entry 5212 (class 1259 OID 21994)
-- Name: idx_audit_logs_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_company_created ON public.audit_logs USING btree (company_id, created_at DESC);


--
-- TOC entry 5213 (class 1259 OID 17594)
-- Name: idx_audit_logs_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_company_id ON public.audit_logs USING btree (company_id);


--
-- TOC entry 5214 (class 1259 OID 17598)
-- Name: idx_audit_logs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at);


--
-- TOC entry 5215 (class 1259 OID 17596)
-- Name: idx_audit_logs_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_entity ON public.audit_logs USING btree (entity_type, entity_id);


--
-- TOC entry 5216 (class 1259 OID 21995)
-- Name: idx_audit_logs_table_record; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_table_record ON public.audit_logs USING btree (table_name, record_id, created_at DESC);


--
-- TOC entry 5217 (class 1259 OID 21996)
-- Name: idx_audit_logs_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_user_created ON public.audit_logs USING btree (user_id, created_at DESC);


--
-- TOC entry 5218 (class 1259 OID 17595)
-- Name: idx_audit_logs_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_user_id ON public.audit_logs USING btree (user_id);


--
-- TOC entry 5787 (class 1259 OID 36536)
-- Name: idx_cl_descendant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cl_descendant ON public.company_links USING btree (descendant_id, depth);


--
-- TOC entry 5398 (class 1259 OID 22205)
-- Name: idx_claim_types_company_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claim_types_company_active ON public.claim_types USING btree (company_id, is_active);


--
-- TOC entry 5399 (class 1259 OID 22206)
-- Name: idx_claim_types_company_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_claim_types_company_code ON public.claim_types USING btree (company_id, code);


--
-- TOC entry 5188 (class 1259 OID 21900)
-- Name: idx_companies_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_companies_active ON public.companies USING btree (is_active) WHERE (is_active = true);


--
-- TOC entry 5189 (class 1259 OID 17519)
-- Name: idx_companies_active_not_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_companies_active_not_deleted ON public.companies USING btree (is_active) WHERE (is_deleted = false);


--
-- TOC entry 5190 (class 1259 OID 36519)
-- Name: idx_companies_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_companies_parent ON public.companies USING btree (parent_company_id);


--
-- TOC entry 5191 (class 1259 OID 17518)
-- Name: idx_companies_subscription_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_companies_subscription_status ON public.companies USING btree (subscription_status);


--
-- TOC entry 5415 (class 1259 OID 22391)
-- Name: idx_company_notification_settings_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_notification_settings_company ON public.company_notification_settings USING btree (company_id, is_active);


--
-- TOC entry 5416 (class 1259 OID 22392)
-- Name: idx_company_notification_settings_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_notification_settings_event ON public.company_notification_settings USING btree (event_type);


--
-- TOC entry 5452 (class 1259 OID 23348)
-- Name: idx_competencies_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_competencies_category ON public.competencies USING btree (category_id);


--
-- TOC entry 5453 (class 1259 OID 23347)
-- Name: idx_competencies_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_competencies_company ON public.competencies USING btree (company_id);


--
-- TOC entry 5447 (class 1259 OID 23322)
-- Name: idx_competency_categories_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_competency_categories_company ON public.competency_categories USING btree (company_id);


--
-- TOC entry 5496 (class 1259 OID 23561)
-- Name: idx_competency_ratings_competency; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_competency_ratings_competency ON public.appraisal_competency_ratings USING btree (competency_id);


--
-- TOC entry 5497 (class 1259 OID 23560)
-- Name: idx_competency_ratings_review; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_competency_ratings_review ON public.appraisal_competency_ratings USING btree (review_id);


--
-- TOC entry 5560 (class 1259 OID 26728)
-- Name: idx_cost_centers_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cost_centers_active ON public.cost_centers USING btree (company_id, is_active) WHERE (deleted_at IS NULL);


--
-- TOC entry 5561 (class 1259 OID 26727)
-- Name: idx_cost_centers_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cost_centers_company ON public.cost_centers USING btree (company_id);


--
-- TOC entry 5562 (class 1259 OID 26729)
-- Name: idx_cost_centers_name_ci; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cost_centers_name_ci ON public.cost_centers USING btree (company_id, lower(name)) WHERE (deleted_at IS NULL);


--
-- TOC entry 5221 (class 1259 OID 18773)
-- Name: idx_departments_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departments_company ON public.departments USING btree (company_id);


--
-- TOC entry 5222 (class 1259 OID 21904)
-- Name: idx_departments_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departments_company_id ON public.departments USING btree (company_id);


--
-- TOC entry 5223 (class 1259 OID 18776)
-- Name: idx_departments_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departments_is_active ON public.departments USING btree (is_active);


--
-- TOC entry 5224 (class 1259 OID 18775)
-- Name: idx_departments_manager; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departments_manager ON public.departments USING btree (manager_id);


--
-- TOC entry 5225 (class 1259 OID 18774)
-- Name: idx_departments_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departments_parent ON public.departments USING btree (parent_department_id);


--
-- TOC entry 5687 (class 1259 OID 32379)
-- Name: idx_device_register_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_device_register_company ON public.device_register USING btree (company_id);


--
-- TOC entry 5688 (class 1259 OID 32380)
-- Name: idx_device_register_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_device_register_employee ON public.device_register USING btree (employee_id);


--
-- TOC entry 5676 (class 1259 OID 32237)
-- Name: idx_emp_shifts_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emp_shifts_company ON public.employee_shifts USING btree (company_id);


--
-- TOC entry 5677 (class 1259 OID 32238)
-- Name: idx_emp_shifts_employee_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emp_shifts_employee_date ON public.employee_shifts USING btree (employee_id, work_date);


--
-- TOC entry 5678 (class 1259 OID 32239)
-- Name: idx_emp_shifts_template; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emp_shifts_template ON public.employee_shifts USING btree (shift_template_id);


--
-- TOC entry 5593 (class 1259 OID 29259)
-- Name: idx_employee_actions_emp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_actions_emp ON public.employee_actions USING btree (company_id, employee_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5599 (class 1259 OID 29405)
-- Name: idx_employee_addresses_emp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_addresses_emp ON public.employee_addresses USING btree (company_id, employee_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5266 (class 1259 OID 19073)
-- Name: idx_employee_allowances_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_allowances_company ON public.employee_allowances USING btree (company_id);


--
-- TOC entry 5267 (class 1259 OID 19075)
-- Name: idx_employee_allowances_effective; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_allowances_effective ON public.employee_allowances USING btree (effective_from);


--
-- TOC entry 5268 (class 1259 OID 19074)
-- Name: idx_employee_allowances_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_allowances_employee ON public.employee_allowances USING btree (employee_id);


--
-- TOC entry 5609 (class 1259 OID 29630)
-- Name: idx_employee_bank_accounts_emp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_bank_accounts_emp ON public.employee_bank_accounts USING btree (company_id, employee_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5402 (class 1259 OID 22255)
-- Name: idx_employee_claims_claim_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_claims_claim_type ON public.employee_claims USING btree (claim_type_id);


--
-- TOC entry 5403 (class 1259 OID 22251)
-- Name: idx_employee_claims_company_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_claims_company_date ON public.employee_claims USING btree (company_id, claim_date DESC);


--
-- TOC entry 5404 (class 1259 OID 22741)
-- Name: idx_employee_claims_company_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_claims_company_status ON public.employee_claims USING btree (company_id, status);


--
-- TOC entry 5405 (class 1259 OID 22252)
-- Name: idx_employee_claims_employee_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_claims_employee_date ON public.employee_claims USING btree (employee_id, claim_date DESC);


--
-- TOC entry 5406 (class 1259 OID 22740)
-- Name: idx_employee_claims_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_claims_status ON public.employee_claims USING btree (status);


--
-- TOC entry 5606 (class 1259 OID 29546)
-- Name: idx_employee_compensation_emp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_compensation_emp ON public.employee_compensation USING btree (company_id, employee_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5273 (class 1259 OID 19170)
-- Name: idx_employee_documents_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_documents_company ON public.employee_documents USING btree (company_id);


--
-- TOC entry 5274 (class 1259 OID 19173)
-- Name: idx_employee_documents_confidential; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_documents_confidential ON public.employee_documents USING btree (is_confidential);


--
-- TOC entry 5275 (class 1259 OID 19171)
-- Name: idx_employee_documents_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_documents_employee ON public.employee_documents USING btree (employee_id);


--
-- TOC entry 5276 (class 1259 OID 19174)
-- Name: idx_employee_documents_is_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_documents_is_deleted ON public.employee_documents USING btree (is_deleted);


--
-- TOC entry 5277 (class 1259 OID 19172)
-- Name: idx_employee_documents_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_documents_type ON public.employee_documents USING btree (document_type);


--
-- TOC entry 5475 (class 1259 OID 23484)
-- Name: idx_employee_goals_appraisal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_goals_appraisal ON public.employee_goals USING btree (appraisal_id);


--
-- TOC entry 5476 (class 1259 OID 23482)
-- Name: idx_employee_goals_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_goals_company ON public.employee_goals USING btree (company_id);


--
-- TOC entry 5477 (class 1259 OID 23483)
-- Name: idx_employee_goals_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_goals_employee ON public.employee_goals USING btree (employee_id);


--
-- TOC entry 5478 (class 1259 OID 23487)
-- Name: idx_employee_goals_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_goals_parent ON public.employee_goals USING btree (parent_goal_id);


--
-- TOC entry 5479 (class 1259 OID 23485)
-- Name: idx_employee_goals_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_goals_period ON public.employee_goals USING btree (period_id);


--
-- TOC entry 5480 (class 1259 OID 23486)
-- Name: idx_employee_goals_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_goals_status ON public.employee_goals USING btree (employee_id, status) WHERE (deleted_at IS NULL);


--
-- TOC entry 5280 (class 1259 OID 19279)
-- Name: idx_employee_history_change_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_history_change_type ON public.employee_history USING btree (change_type);


--
-- TOC entry 5281 (class 1259 OID 19277)
-- Name: idx_employee_history_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_history_company ON public.employee_history USING btree (company_id);


--
-- TOC entry 5282 (class 1259 OID 19280)
-- Name: idx_employee_history_effective_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_history_effective_date ON public.employee_history USING btree (effective_date);


--
-- TOC entry 5283 (class 1259 OID 19278)
-- Name: idx_employee_history_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_history_employee ON public.employee_history USING btree (employee_id);


--
-- TOC entry 5371 (class 1259 OID 20255)
-- Name: idx_employee_loans_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_loans_company ON public.employee_loans USING btree (company_id);


--
-- TOC entry 5372 (class 1259 OID 20256)
-- Name: idx_employee_loans_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_loans_employee ON public.employee_loans USING btree (employee_id);


--
-- TOC entry 5373 (class 1259 OID 20257)
-- Name: idx_employee_loans_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_loans_status ON public.employee_loans USING btree (status);


--
-- TOC entry 5555 (class 1259 OID 37100)
-- Name: idx_employee_shift_assignments_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_shift_assignments_company_created ON public.employee_shift_assignments USING btree (company_id, created_at);


--
-- TOC entry 5679 (class 1259 OID 37099)
-- Name: idx_employee_shifts_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_shifts_company_created ON public.employee_shifts USING btree (company_id, created_at);


--
-- TOC entry 5602 (class 1259 OID 37101)
-- Name: idx_employee_work_schedules_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_work_schedules_company_created ON public.employee_work_schedules USING btree (company_id, created_at);


--
-- TOC entry 5242 (class 1259 OID 21903)
-- Name: idx_employees_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_active ON public.employees USING btree (company_id, is_deleted) WHERE (is_deleted = false);


--
-- TOC entry 5243 (class 1259 OID 18952)
-- Name: idx_employees_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_company ON public.employees USING btree (company_id);


--
-- TOC entry 5244 (class 1259 OID 21901)
-- Name: idx_employees_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_company_id ON public.employees USING btree (company_id);


--
-- TOC entry 5245 (class 1259 OID 26902)
-- Name: idx_employees_company_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_company_location ON public.employees USING btree (company_id, work_location_id) WHERE ((work_location_id IS NOT NULL) AND (deleted_at IS NULL));


--
-- TOC entry 5246 (class 1259 OID 26901)
-- Name: idx_employees_company_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_company_status ON public.employees USING btree (company_id, employment_status) WHERE (deleted_at IS NULL);


--
-- TOC entry 5247 (class 1259 OID 26760)
-- Name: idx_employees_cost_center; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_cost_center ON public.employees USING btree (company_id, cost_center_id) WHERE (cost_center_id IS NOT NULL);


--
-- TOC entry 5248 (class 1259 OID 18953)
-- Name: idx_employees_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_department ON public.employees USING btree (department_id);


--
-- TOC entry 5249 (class 1259 OID 18958)
-- Name: idx_employees_full_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_full_name ON public.employees USING btree (full_name);


--
-- TOC entry 5250 (class 1259 OID 18959)
-- Name: idx_employees_ic_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_ic_number ON public.employees USING btree (ic_number);


--
-- TOC entry 5251 (class 1259 OID 18957)
-- Name: idx_employees_is_deleted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_is_deleted ON public.employees USING btree (is_deleted);


--
-- TOC entry 5252 (class 1259 OID 18955)
-- Name: idx_employees_manager; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_manager ON public.employees USING btree (manager_id);


--
-- TOC entry 5253 (class 1259 OID 35299)
-- Name: idx_employees_manager_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_manager_id ON public.employees USING btree (manager_id);


--
-- TOC entry 5254 (class 1259 OID 21902)
-- Name: idx_employees_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_number ON public.employees USING btree (company_id, employee_number);


--
-- TOC entry 5255 (class 1259 OID 18954)
-- Name: idx_employees_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_position ON public.employees USING btree (position_id);


--
-- TOC entry 5256 (class 1259 OID 22719)
-- Name: idx_employees_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_status ON public.employees USING btree (employment_status);


--
-- TOC entry 5354 (class 1259 OID 21910)
-- Name: idx_epf_rates_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_epf_rates_dates ON public.epf_rates USING btree (effective_from, effective_to, is_active);


--
-- TOC entry 5355 (class 1259 OID 20189)
-- Name: idx_epf_rates_effective_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_epf_rates_effective_dates ON public.epf_rates USING btree (effective_from, effective_to);


--
-- TOC entry 5356 (class 1259 OID 20190)
-- Name: idx_epf_rates_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_epf_rates_is_active ON public.epf_rates USING btree (is_active);


--
-- TOC entry 5784 (class 1259 OID 35842)
-- Name: idx_func_members_by_tag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_func_members_by_tag ON public.employee_function_memberships USING btree (company_id, function_tag_id);


--
-- TOC entry 5683 (class 1259 OID 32310)
-- Name: idx_geo_locations_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_geo_locations_company ON public.geo_locations USING btree (company_id);


--
-- TOC entry 5570 (class 1259 OID 27381)
-- Name: idx_gl_accounts_company_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gl_accounts_company_active ON public.gl_accounts USING btree (company_id, is_active) WHERE (deleted_at IS NULL);


--
-- TOC entry 5571 (class 1259 OID 27382)
-- Name: idx_gl_accounts_company_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gl_accounts_company_category ON public.gl_accounts USING btree (company_id, category) WHERE (deleted_at IS NULL);


--
-- TOC entry 5584 (class 1259 OID 27527)
-- Name: idx_gl_journal_headers_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gl_journal_headers_company ON public.gl_journal_headers USING btree (company_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5588 (class 1259 OID 27765)
-- Name: idx_gl_journal_lines_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gl_journal_lines_company ON public.gl_journal_lines USING btree (company_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5483 (class 1259 OID 23505)
-- Name: idx_goal_milestones_goal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_goal_milestones_goal ON public.goal_milestones USING btree (goal_id);


--
-- TOC entry 5504 (class 1259 OID 23586)
-- Name: idx_goal_ratings_goal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_goal_ratings_goal ON public.appraisal_goal_ratings USING btree (goal_id);


--
-- TOC entry 5505 (class 1259 OID 23585)
-- Name: idx_goal_ratings_review; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_goal_ratings_review ON public.appraisal_goal_ratings USING btree (review_id);


--
-- TOC entry 5733 (class 1259 OID 34117)
-- Name: idx_hc_plan_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hc_plan_company ON public.headcount_plans USING btree (company_id);


--
-- TOC entry 5734 (class 1259 OID 34118)
-- Name: idx_hc_plan_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hc_plan_period ON public.headcount_plans USING btree (period_start, period_end);


--
-- TOC entry 5760 (class 1259 OID 34859)
-- Name: idx_hreq_appr_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hreq_appr_company ON public.headcount_approvals USING btree (company_id, level_no, status);


--
-- TOC entry 5753 (class 1259 OID 34789)
-- Name: idx_hreq_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hreq_company ON public.headcount_requests USING btree (company_id);


--
-- TOC entry 5754 (class 1259 OID 34793)
-- Name: idx_hreq_cost_center; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hreq_cost_center ON public.headcount_requests USING btree (cost_center_id);


--
-- TOC entry 5755 (class 1259 OID 34792)
-- Name: idx_hreq_policy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hreq_policy ON public.headcount_requests USING btree (policy_id);


--
-- TOC entry 5756 (class 1259 OID 34791)
-- Name: idx_hreq_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hreq_position ON public.headcount_requests USING btree (position_id);


--
-- TOC entry 5757 (class 1259 OID 34790)
-- Name: idx_hreq_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hreq_status ON public.headcount_requests USING btree (status, urgency);


--
-- TOC entry 5596 (class 1259 OID 29337)
-- Name: idx_job_assignments_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_assignments_employee ON public.employee_job_assignments USING btree (company_id, employee_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5617 (class 1259 OID 29826)
-- Name: idx_job_catalog_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_catalog_company ON public.job_catalog USING btree (company_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5618 (class 1259 OID 29827)
-- Name: idx_job_catalog_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_catalog_role ON public.job_catalog USING btree (company_id, job_role) WHERE (deleted_at IS NULL);


--
-- TOC entry 5770 (class 1259 OID 35029)
-- Name: idx_jreq_appr_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jreq_appr_company ON public.job_requisition_approvals USING btree (company_id, level_no, status);


--
-- TOC entry 5762 (class 1259 OID 34957)
-- Name: idx_jreq_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jreq_company ON public.job_requisitions USING btree (company_id);


--
-- TOC entry 5763 (class 1259 OID 34962)
-- Name: idx_jreq_cost_center; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jreq_cost_center ON public.job_requisitions USING btree (cost_center_id);


--
-- TOC entry 5764 (class 1259 OID 34960)
-- Name: idx_jreq_hiring_manager; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jreq_hiring_manager ON public.job_requisitions USING btree (hiring_manager_id);


--
-- TOC entry 5765 (class 1259 OID 34961)
-- Name: idx_jreq_policy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jreq_policy ON public.job_requisitions USING btree (policy_id);


--
-- TOC entry 5766 (class 1259 OID 34959)
-- Name: idx_jreq_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jreq_position ON public.job_requisitions USING btree (position_id);


--
-- TOC entry 5767 (class 1259 OID 34958)
-- Name: idx_jreq_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jreq_status ON public.job_requisitions USING btree (status);


--
-- TOC entry 5707 (class 1259 OID 32878)
-- Name: idx_kiosk_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kiosk_active ON public.kiosk_sessions USING btree (is_active);


--
-- TOC entry 5708 (class 1259 OID 32875)
-- Name: idx_kiosk_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kiosk_company ON public.kiosk_sessions USING btree (company_id);


--
-- TOC entry 5709 (class 1259 OID 32877)
-- Name: idx_kiosk_device; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kiosk_device ON public.kiosk_sessions USING btree (device_id);


--
-- TOC entry 5710 (class 1259 OID 32876)
-- Name: idx_kiosk_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kiosk_location ON public.kiosk_sessions USING btree (geo_location_id);


--
-- TOC entry 5313 (class 1259 OID 36083)
-- Name: idx_lah_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lah_company_created ON public.leave_approval_history USING btree (company_id, created_at);


--
-- TOC entry 5666 (class 1259 OID 31815)
-- Name: idx_leave_accrual_log_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_accrual_log_company ON public.leave_accrual_log USING btree (company_id, employee_id, leave_type_id);


--
-- TOC entry 5663 (class 1259 OID 31740)
-- Name: idx_leave_accrual_runs_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_accrual_runs_company ON public.leave_accrual_runs USING btree (company_id, status, period_start);


--
-- TOC entry 5324 (class 1259 OID 19820)
-- Name: idx_leave_adjust_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_adjust_company ON public.leave_balance_adjustments USING btree (company_id);


--
-- TOC entry 5325 (class 1259 OID 19821)
-- Name: idx_leave_adjust_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_adjust_employee ON public.leave_balance_adjustments USING btree (employee_id);


--
-- TOC entry 5326 (class 1259 OID 19822)
-- Name: idx_leave_adjust_entitlement; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_adjust_entitlement ON public.leave_balance_adjustments USING btree (leave_entitlement_id);


--
-- TOC entry 5301 (class 1259 OID 19742)
-- Name: idx_leave_app_approver; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_app_approver ON public.leave_applications USING btree (approver_id);


--
-- TOC entry 5302 (class 1259 OID 19737)
-- Name: idx_leave_app_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_app_company ON public.leave_applications USING btree (company_id);


--
-- TOC entry 5303 (class 1259 OID 19741)
-- Name: idx_leave_app_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_app_dates ON public.leave_applications USING btree (start_date, end_date);


--
-- TOC entry 5304 (class 1259 OID 19738)
-- Name: idx_leave_app_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_app_employee ON public.leave_applications USING btree (employee_id);


--
-- TOC entry 5305 (class 1259 OID 19740)
-- Name: idx_leave_app_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_app_status ON public.leave_applications USING btree (status);


--
-- TOC entry 5306 (class 1259 OID 19739)
-- Name: idx_leave_app_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_app_type ON public.leave_applications USING btree (leave_type_id);


--
-- TOC entry 5307 (class 1259 OID 22895)
-- Name: idx_leave_applications_company_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_applications_company_status ON public.leave_applications USING btree (company_id, status);


--
-- TOC entry 5308 (class 1259 OID 21908)
-- Name: idx_leave_applications_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_applications_dates ON public.leave_applications USING btree (company_id, start_date, end_date);


--
-- TOC entry 5309 (class 1259 OID 21907)
-- Name: idx_leave_applications_emp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_applications_emp ON public.leave_applications USING btree (company_id, employee_id);


--
-- TOC entry 5310 (class 1259 OID 21909)
-- Name: idx_leave_applications_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_applications_status ON public.leave_applications USING btree (status);


--
-- TOC entry 5314 (class 1259 OID 19763)
-- Name: idx_leave_approval_application; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_approval_application ON public.leave_approval_history USING btree (leave_application_id);


--
-- TOC entry 5315 (class 1259 OID 36017)
-- Name: idx_leave_approval_history_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_approval_history_company_id ON public.leave_approval_history USING btree (company_id);


--
-- TOC entry 5316 (class 1259 OID 19764)
-- Name: idx_leave_approval_performer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_approval_performer ON public.leave_approval_history USING btree (performed_by);


--
-- TOC entry 5647 (class 1259 OID 31359)
-- Name: idx_leave_approvals_req; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_approvals_req ON public.leave_approvals USING btree (company_id, request_id, level) WHERE (deleted_at IS NULL);


--
-- TOC entry 5319 (class 1259 OID 19788)
-- Name: idx_leave_blackout_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_blackout_company ON public.leave_blackout_periods USING btree (company_id);


--
-- TOC entry 5320 (class 1259 OID 19789)
-- Name: idx_leave_blackout_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_blackout_dates ON public.leave_blackout_periods USING btree (start_date, end_date);


--
-- TOC entry 5321 (class 1259 OID 19790)
-- Name: idx_leave_blackout_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_blackout_is_active ON public.leave_blackout_periods USING btree (is_active);


--
-- TOC entry 5652 (class 1259 OID 31422)
-- Name: idx_leave_cancel_history_req; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_cancel_history_req ON public.leave_cancel_history USING btree (company_id, request_id, cancelled_at);


--
-- TOC entry 5291 (class 1259 OID 19630)
-- Name: idx_leave_entitlements_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_entitlements_company ON public.leave_entitlements USING btree (company_id);


--
-- TOC entry 5292 (class 1259 OID 37104)
-- Name: idx_leave_entitlements_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_entitlements_company_created ON public.leave_entitlements USING btree (company_id, created_at);


--
-- TOC entry 5293 (class 1259 OID 21906)
-- Name: idx_leave_entitlements_emp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_entitlements_emp ON public.leave_entitlements USING btree (company_id, employee_id, year);


--
-- TOC entry 5294 (class 1259 OID 19631)
-- Name: idx_leave_entitlements_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_entitlements_employee ON public.leave_entitlements USING btree (employee_id);


--
-- TOC entry 5295 (class 1259 OID 19632)
-- Name: idx_leave_entitlements_leave_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_entitlements_leave_type ON public.leave_entitlements USING btree (leave_type_id);


--
-- TOC entry 5296 (class 1259 OID 19633)
-- Name: idx_leave_entitlements_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_entitlements_year ON public.leave_entitlements USING btree (year);


--
-- TOC entry 5641 (class 1259 OID 31189)
-- Name: idx_leave_ledger_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_ledger_lookup ON public.leave_ledger USING btree (company_id, employee_id, leave_type_id, year);


--
-- TOC entry 5626 (class 1259 OID 30883)
-- Name: idx_leave_policies_company_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_policies_company_type ON public.leave_policies USING btree (company_id, leave_type_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5630 (class 1259 OID 30950)
-- Name: idx_leave_policy_group_map_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_policy_group_map_company ON public.leave_policy_group_map USING btree (company_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5622 (class 1259 OID 30681)
-- Name: idx_leave_policy_groups_company_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_policy_groups_company_active ON public.leave_policy_groups USING btree (company_id, is_active) WHERE (deleted_at IS NULL);


--
-- TOC entry 5644 (class 1259 OID 31288)
-- Name: idx_leave_requests_emp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_emp ON public.leave_requests USING btree (company_id, employee_id, status, start_date) WHERE (deleted_at IS NULL);


--
-- TOC entry 5284 (class 1259 OID 19554)
-- Name: idx_leave_types_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_types_company ON public.leave_types USING btree (company_id);


--
-- TOC entry 5285 (class 1259 OID 19555)
-- Name: idx_leave_types_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_types_is_active ON public.leave_types USING btree (is_active);


--
-- TOC entry 5407 (class 1259 OID 22357)
-- Name: idx_notification_queue_company_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_queue_company_status ON public.notification_queue USING btree (company_id, status);


--
-- TOC entry 5408 (class 1259 OID 22356)
-- Name: idx_notification_queue_status_sched; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_queue_status_sched ON public.notification_queue USING btree (status, scheduled_at);


--
-- TOC entry 5610 (class 1259 OID 29764)
-- Name: idx_org_units_company_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_org_units_company_active ON public.org_units USING btree (company_id, is_active) WHERE (deleted_at IS NULL);


--
-- TOC entry 5611 (class 1259 OID 29765)
-- Name: idx_org_units_company_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_org_units_company_parent ON public.org_units USING btree (company_id, parent_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5386 (class 1259 OID 35385)
-- Name: idx_ot_appr_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ot_appr_employee ON public.overtime_approvals USING btree (approver_employee_id);


--
-- TOC entry 5387 (class 1259 OID 35509)
-- Name: idx_ot_approvals_status_text; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ot_approvals_status_text ON public.overtime_approvals USING btree (approval_status);


--
-- TOC entry 5388 (class 1259 OID 22131)
-- Name: idx_ot_company_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ot_company_date ON public.overtime_approvals USING btree (company_id, ot_date DESC);


--
-- TOC entry 5389 (class 1259 OID 22132)
-- Name: idx_ot_employee_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ot_employee_date ON public.overtime_approvals USING btree (employee_id, ot_date DESC);


--
-- TOC entry 5531 (class 1259 OID 32692)
-- Name: idx_ot_payroll_batch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ot_payroll_batch ON public.overtime_requests USING btree (payroll_batch_id);


--
-- TOC entry 5390 (class 1259 OID 22754)
-- Name: idx_ot_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ot_status ON public.overtime_approvals USING btree (status);


--
-- TOC entry 5391 (class 1259 OID 22755)
-- Name: idx_ot_status_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ot_status_company ON public.overtime_approvals USING btree (company_id, status);


--
-- TOC entry 5532 (class 1259 OID 24065)
-- Name: idx_overtime_requests_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overtime_requests_company ON public.overtime_requests USING btree (company_id);


--
-- TOC entry 5533 (class 1259 OID 37102)
-- Name: idx_overtime_requests_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overtime_requests_company_created ON public.overtime_requests USING btree (company_id, created_at);


--
-- TOC entry 5534 (class 1259 OID 24068)
-- Name: idx_overtime_requests_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overtime_requests_date ON public.overtime_requests USING btree (overtime_date);


--
-- TOC entry 5535 (class 1259 OID 24066)
-- Name: idx_overtime_requests_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overtime_requests_employee ON public.overtime_requests USING btree (employee_id);


--
-- TOC entry 5536 (class 1259 OID 24067)
-- Name: idx_overtime_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overtime_requests_status ON public.overtime_requests USING btree (company_id, status);


--
-- TOC entry 5334 (class 1259 OID 20027)
-- Name: idx_payroll_batches_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_batches_company ON public.payroll_batches USING btree (company_id);


--
-- TOC entry 5335 (class 1259 OID 22896)
-- Name: idx_payroll_batches_company_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_batches_company_month ON public.payroll_batches USING btree (company_id, payroll_month);


--
-- TOC entry 5336 (class 1259 OID 20028)
-- Name: idx_payroll_batches_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_batches_month ON public.payroll_batches USING btree (payroll_month);


--
-- TOC entry 5337 (class 1259 OID 20030)
-- Name: idx_payroll_batches_pay_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_batches_pay_date ON public.payroll_batches USING btree (pay_date);


--
-- TOC entry 5338 (class 1259 OID 20029)
-- Name: idx_payroll_batches_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_batches_status ON public.payroll_batches USING btree (status);


--
-- TOC entry 5576 (class 1259 OID 27462)
-- Name: idx_payroll_gl_mapping_company_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_gl_mapping_company_active ON public.payroll_component_gl_mappings USING btree (company_id, is_active) WHERE (deleted_at IS NULL);


--
-- TOC entry 5343 (class 1259 OID 20131)
-- Name: idx_payroll_items_batch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_items_batch ON public.payroll_items USING btree (payroll_batch_id);


--
-- TOC entry 5344 (class 1259 OID 20132)
-- Name: idx_payroll_items_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_items_company ON public.payroll_items USING btree (company_id);


--
-- TOC entry 5345 (class 1259 OID 37103)
-- Name: idx_payroll_items_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_items_company_created ON public.payroll_items USING btree (company_id, created_at);


--
-- TOC entry 5346 (class 1259 OID 20133)
-- Name: idx_payroll_items_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_items_employee ON public.payroll_items USING btree (employee_id);


--
-- TOC entry 5347 (class 1259 OID 20134)
-- Name: idx_payroll_items_payment_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_items_payment_status ON public.payroll_items USING btree (payment_status);


--
-- TOC entry 5363 (class 1259 OID 20213)
-- Name: idx_pcb_effective_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pcb_effective_dates ON public.pcb_tax_schedules USING btree (effective_from, effective_to);


--
-- TOC entry 5364 (class 1259 OID 20214)
-- Name: idx_pcb_income_range; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pcb_income_range ON public.pcb_tax_schedules USING btree (monthly_income_from, monthly_income_to);


--
-- TOC entry 5365 (class 1259 OID 20215)
-- Name: idx_pcb_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pcb_is_active ON public.pcb_tax_schedules USING btree (is_active);


--
-- TOC entry 5366 (class 1259 OID 21912)
-- Name: idx_pcb_rates_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pcb_rates_dates ON public.pcb_tax_schedules USING btree (effective_from, effective_to, is_active);


--
-- TOC entry 5723 (class 1259 OID 34039)
-- Name: idx_pos_assign_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_assign_company ON public.position_assignments USING btree (company_id);


--
-- TOC entry 5724 (class 1259 OID 34043)
-- Name: idx_pos_assign_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_assign_dates ON public.position_assignments USING btree (start_date, end_date);


--
-- TOC entry 5725 (class 1259 OID 34041)
-- Name: idx_pos_assign_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_assign_employee ON public.position_assignments USING btree (employee_id);


--
-- TOC entry 5726 (class 1259 OID 34040)
-- Name: idx_pos_assign_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_assign_position ON public.position_assignments USING btree (position_id);


--
-- TOC entry 5727 (class 1259 OID 34042)
-- Name: idx_pos_assign_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_assign_status ON public.position_assignments USING btree (status);


--
-- TOC entry 5736 (class 1259 OID 34227)
-- Name: idx_poshist_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_poshist_company ON public.position_history USING btree (company_id, changed_at);


--
-- TOC entry 5737 (class 1259 OID 34228)
-- Name: idx_poshist_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_poshist_entity ON public.position_history USING btree (entity_type, entity_id);


--
-- TOC entry 5228 (class 1259 OID 18851)
-- Name: idx_positions_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_positions_company ON public.positions USING btree (company_id);


--
-- TOC entry 5229 (class 1259 OID 21905)
-- Name: idx_positions_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_positions_company_id ON public.positions USING btree (company_id);


--
-- TOC entry 5230 (class 1259 OID 18852)
-- Name: idx_positions_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_positions_department ON public.positions USING btree (department_id);


--
-- TOC entry 5231 (class 1259 OID 18853)
-- Name: idx_positions_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_positions_is_active ON public.positions USING btree (is_active);


--
-- TOC entry 5232 (class 1259 OID 34520)
-- Name: idx_positions_role_band; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_positions_role_band ON public.positions USING btree (role_band);


--
-- TOC entry 5233 (class 1259 OID 33223)
-- Name: idx_positions_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_positions_status ON public.positions USING btree (status);


--
-- TOC entry 5329 (class 1259 OID 19931)
-- Name: idx_public_holidays_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_public_holidays_company ON public.public_holidays USING btree (company_id);


--
-- TOC entry 5330 (class 1259 OID 19932)
-- Name: idx_public_holidays_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_public_holidays_date ON public.public_holidays USING btree (holiday_date);


--
-- TOC entry 5331 (class 1259 OID 19933)
-- Name: idx_public_holidays_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_public_holidays_is_active ON public.public_holidays USING btree (is_active);


--
-- TOC entry 5704 (class 1259 OID 32801)
-- Name: idx_qr_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qr_company ON public.attendance_qr_tokens USING btree (company_id);


--
-- TOC entry 5705 (class 1259 OID 32802)
-- Name: idx_qr_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qr_location ON public.attendance_qr_tokens USING btree (geo_location_id);


--
-- TOC entry 5432 (class 1259 OID 23263)
-- Name: idx_rating_scale_values_scale; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rating_scale_values_scale ON public.rating_scale_values USING btree (rating_scale_id);


--
-- TOC entry 5426 (class 1259 OID 23243)
-- Name: idx_rating_scales_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rating_scales_active ON public.rating_scales USING btree (company_id, is_active) WHERE (deleted_at IS NULL);


--
-- TOC entry 5427 (class 1259 OID 23242)
-- Name: idx_rating_scales_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rating_scales_company ON public.rating_scales USING btree (company_id);


--
-- TOC entry 5716 (class 1259 OID 33058)
-- Name: idx_scan_attendance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_scan_attendance ON public.attendance_scan_logs USING btree (attendance_record_id);


--
-- TOC entry 5717 (class 1259 OID 33057)
-- Name: idx_scan_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_scan_company_created ON public.attendance_scan_logs USING btree (company_id, created_at);


--
-- TOC entry 5718 (class 1259 OID 33060)
-- Name: idx_scan_device; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_scan_device ON public.attendance_scan_logs USING btree (device_id);


--
-- TOC entry 5719 (class 1259 OID 33059)
-- Name: idx_scan_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_scan_employee ON public.attendance_scan_logs USING btree (employee_id);


--
-- TOC entry 5720 (class 1259 OID 33062)
-- Name: idx_scan_kiosk; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_scan_kiosk ON public.attendance_scan_logs USING btree (kiosk_session_id);


--
-- TOC entry 5721 (class 1259 OID 33061)
-- Name: idx_scan_qr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_scan_qr ON public.attendance_scan_logs USING btree (qr_token_id);


--
-- TOC entry 5201 (class 1259 OID 36084)
-- Name: idx_sessions_company_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sessions_company_created ON public.user_sessions USING btree (company_id, created_at);


--
-- TOC entry 5544 (class 1259 OID 24351)
-- Name: idx_shift_templates_company_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_templates_company_active ON public.shift_templates USING btree (company_id, is_active) WHERE (deleted_at IS NULL);


--
-- TOC entry 5545 (class 1259 OID 24350)
-- Name: idx_shift_templates_company_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_shift_templates_company_code ON public.shift_templates USING btree (company_id, code) WHERE (deleted_at IS NULL);


--
-- TOC entry 5546 (class 1259 OID 32144)
-- Name: idx_shift_templates_work_schedule; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_templates_work_schedule ON public.shift_templates USING btree (work_schedule_id);


--
-- TOC entry 5357 (class 1259 OID 21911)
-- Name: idx_socso_rates_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_socso_rates_dates ON public.socso_contribution_rates USING btree (effective_from, effective_to, is_active);


--
-- TOC entry 5358 (class 1259 OID 20200)
-- Name: idx_socso_rates_effective_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_socso_rates_effective_dates ON public.socso_contribution_rates USING btree (effective_from, effective_to);


--
-- TOC entry 5359 (class 1259 OID 20202)
-- Name: idx_socso_rates_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_socso_rates_is_active ON public.socso_contribution_rates USING btree (is_active);


--
-- TOC entry 5360 (class 1259 OID 20201)
-- Name: idx_socso_rates_wage_range; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_socso_rates_wage_range ON public.socso_contribution_rates USING btree (wage_from, wage_to);


--
-- TOC entry 5181 (class 1259 OID 17487)
-- Name: idx_subscription_plans_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_subscription_plans_code ON public.subscription_plans USING btree (code);


--
-- TOC entry 5460 (class 1259 OID 23372)
-- Name: idx_template_competencies_competency; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_template_competencies_competency ON public.appraisal_template_competencies USING btree (competency_id);


--
-- TOC entry 5461 (class 1259 OID 23371)
-- Name: idx_template_competencies_template; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_template_competencies_template ON public.appraisal_template_competencies USING btree (template_id);


--
-- TOC entry 5202 (class 1259 OID 36018)
-- Name: idx_user_sessions_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_sessions_company_id ON public.user_sessions USING btree (company_id);


--
-- TOC entry 5203 (class 1259 OID 17574)
-- Name: idx_user_sessions_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_sessions_expires_at ON public.user_sessions USING btree (expires_at);


--
-- TOC entry 5204 (class 1259 OID 17573)
-- Name: idx_user_sessions_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_sessions_token ON public.user_sessions USING btree (token);


--
-- TOC entry 5205 (class 1259 OID 17572)
-- Name: idx_user_sessions_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_sessions_user_id ON public.user_sessions USING btree (user_id);


--
-- TOC entry 5192 (class 1259 OID 17554)
-- Name: idx_users_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_active ON public.users USING btree (is_active);


--
-- TOC entry 5193 (class 1259 OID 17550)
-- Name: idx_users_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_company_id ON public.users USING btree (company_id);


--
-- TOC entry 5194 (class 1259 OID 17551)
-- Name: idx_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_email ON public.users USING btree (email);


--
-- TOC entry 5195 (class 1259 OID 17552)
-- Name: idx_users_employee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_employee_id ON public.users USING btree (employee_id);


--
-- TOC entry 5196 (class 1259 OID 17553)
-- Name: idx_users_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_role ON public.users USING btree (role);


--
-- TOC entry 5539 (class 1259 OID 24330)
-- Name: idx_work_locations_company_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_locations_company_active ON public.work_locations USING btree (company_id, is_active) WHERE (deleted_at IS NULL);


--
-- TOC entry 5540 (class 1259 OID 24329)
-- Name: idx_work_locations_company_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_work_locations_company_code ON public.work_locations USING btree (company_id, code) WHERE (deleted_at IS NULL);


--
-- TOC entry 5669 (class 1259 OID 31970)
-- Name: idx_work_schedules_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedules_company ON public.work_schedules USING btree (company_id);


--
-- TOC entry 5603 (class 1259 OID 29475)
-- Name: idx_work_schedules_emp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedules_emp ON public.employee_work_schedules USING btree (company_id, employee_id) WHERE (deleted_at IS NULL);


--
-- TOC entry 5527 (class 1259 OID 24042)
-- Name: idx_zakat_rates_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_zakat_rates_active ON public.zakat_rates USING btree (is_active, effective_from, effective_to);


--
-- TOC entry 5528 (class 1259 OID 24043)
-- Name: idx_zakat_rates_range; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_zakat_rates_range ON public.zakat_rates USING btree (income_from, income_to);


--
-- TOC entry 5750 (class 1259 OID 34660)
-- Name: uix_ap_assign_default; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_ap_assign_default ON public.approval_policy_assignments USING btree (company_id, action_type) WHERE ((is_default = true) AND (deleted_at IS NULL));


--
-- TOC entry 5746 (class 1259 OID 34627)
-- Name: uix_ap_levels_policy_level; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_ap_levels_policy_level ON public.approval_policy_levels USING btree (policy_id, level_no);


--
-- TOC entry 5743 (class 1259 OID 34599)
-- Name: uix_ap_policies_company_action_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_ap_policies_company_action_name ON public.approval_policies USING btree (company_id, action_type, lower(name)) WHERE (deleted_at IS NULL);


--
-- TOC entry 5689 (class 1259 OID 32381)
-- Name: uix_device_fp_company; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_device_fp_company ON public.device_register USING btree (company_id, device_fingerprint) WHERE ((device_fingerprint IS NOT NULL) AND (deleted_at IS NULL));


--
-- TOC entry 5680 (class 1259 OID 32240)
-- Name: uix_emp_shifts_unique_day; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_emp_shifts_unique_day ON public.employee_shifts USING btree (company_id, employee_id, work_date) WHERE (deleted_at IS NULL);


--
-- TOC entry 5776 (class 1259 OID 35136)
-- Name: uix_fn_tag_company; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_fn_tag_company ON public.approval_function_tags USING btree (company_id, lower(tag));


--
-- TOC entry 5684 (class 1259 OID 32311)
-- Name: uix_geo_locations_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_geo_locations_name ON public.geo_locations USING btree (company_id, lower(name)) WHERE (deleted_at IS NULL);


--
-- TOC entry 5735 (class 1259 OID 34116)
-- Name: uix_hc_plan_company_cc_period; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_hc_plan_company_cc_period ON public.headcount_plans USING btree (company_id, cost_center_id, period_start, period_end) WHERE (deleted_at IS NULL);


--
-- TOC entry 5761 (class 1259 OID 34858)
-- Name: uix_hreq_appr_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_hreq_appr_unique ON public.headcount_approvals USING btree (headcount_request_id, level_no, approver_employee_id);


--
-- TOC entry 5773 (class 1259 OID 35028)
-- Name: uix_jreq_appr_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_jreq_appr_unique ON public.job_requisition_approvals USING btree (job_requisition_id, level_no, approver_employee_id);


--
-- TOC entry 5730 (class 1259 OID 34048)
-- Name: uix_pos_assign_one_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_pos_assign_one_primary ON public.position_assignments USING btree (employee_id) WHERE ((is_primary = true) AND (status = 'active'::text) AND (deleted_at IS NULL));


--
-- TOC entry 5236 (class 1259 OID 33222)
-- Name: uix_positions_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_positions_code ON public.positions USING btree (company_id, lower((code)::text)) WHERE (deleted_at IS NULL);


--
-- TOC entry 5706 (class 1259 OID 32803)
-- Name: uix_qr_company_token_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_qr_company_token_active ON public.attendance_qr_tokens USING btree (company_id, token) WHERE (deleted_at IS NULL);


--
-- TOC entry 5670 (class 1259 OID 31971)
-- Name: uix_work_schedules_default; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_work_schedules_default ON public.work_schedules USING btree (company_id) WHERE ((is_default = true) AND (deleted_at IS NULL));


--
-- TOC entry 5671 (class 1259 OID 31972)
-- Name: uix_work_schedules_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uix_work_schedules_name ON public.work_schedules USING btree (company_id, lower(name)) WHERE (deleted_at IS NULL);


--
-- TOC entry 5563 (class 1259 OID 26754)
-- Name: uq_cost_centers_company_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_cost_centers_company_id_id ON public.cost_centers USING btree (company_id, id);


--
-- TOC entry 5637 (class 1259 OID 31047)
-- Name: uq_employee_leave_entitlements; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_employee_leave_entitlements ON public.employee_leave_entitlements USING btree (company_id, employee_id, leave_type_id, effective_from) WHERE (deleted_at IS NULL);


--
-- TOC entry 5261 (class 1259 OID 27642)
-- Name: uq_employees_company_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_employees_company_id_id ON public.employees USING btree (company_id, id);


--
-- TOC entry 5262 (class 1259 OID 27122)
-- Name: uq_employees_company_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_employees_company_number ON public.employees USING btree (company_id, employee_number) WHERE (deleted_at IS NULL);


--
-- TOC entry 5263 (class 1259 OID 26903)
-- Name: uq_employees_company_work_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_employees_company_work_email ON public.employees USING btree (company_id, lower((work_email)::text)) WHERE ((work_email IS NOT NULL) AND (deleted_at IS NULL));


--
-- TOC entry 5574 (class 1259 OID 27375)
-- Name: uq_gl_accounts_company_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_gl_accounts_company_id_id ON public.gl_accounts USING btree (company_id, id);


--
-- TOC entry 5575 (class 1259 OID 27446)
-- Name: uq_gl_accounts_company_id_id2; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_gl_accounts_company_id_id2 ON public.gl_accounts USING btree (company_id, id);


--
-- TOC entry 5621 (class 1259 OID 29825)
-- Name: uq_job_catalog_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_job_catalog_unique ON public.job_catalog USING btree (company_id, job_family, job_role, job_grade) WHERE (deleted_at IS NULL);


--
-- TOC entry 5585 (class 1259 OID 27526)
-- Name: uq_journal_company_journal_no; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_journal_company_journal_no ON public.gl_journal_headers USING btree (company_id, journal_no) WHERE ((journal_no IS NOT NULL) AND (deleted_at IS NULL));


--
-- TOC entry 5640 (class 1259 OID 31120)
-- Name: uq_leave_balances_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_leave_balances_key ON public.leave_balances USING btree (company_id, employee_id, leave_type_id, year) WHERE (deleted_at IS NULL);


--
-- TOC entry 5629 (class 1259 OID 30882)
-- Name: uq_leave_policies_company_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_leave_policies_company_code ON public.leave_policies USING btree (company_id, policy_code) WHERE (deleted_at IS NULL);


--
-- TOC entry 5625 (class 1259 OID 30680)
-- Name: uq_leave_policy_groups_company_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_leave_policy_groups_company_code ON public.leave_policy_groups USING btree (company_id, code) WHERE (deleted_at IS NULL);


--
-- TOC entry 5290 (class 1259 OID 30600)
-- Name: uq_leave_types_company_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_leave_types_company_code ON public.leave_types USING btree (company_id, code) WHERE (deleted_at IS NULL);


--
-- TOC entry 5616 (class 1259 OID 29758)
-- Name: uq_org_units_company_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_org_units_company_id_id ON public.org_units USING btree (company_id, id);


--
-- TOC entry 5579 (class 1259 OID 27445)
-- Name: uq_payroll_component_gl_mappings; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_payroll_component_gl_mappings ON public.payroll_component_gl_mappings USING btree (company_id, component_code) WHERE (deleted_at IS NULL);


--
-- TOC entry 5239 (class 1259 OID 30064)
-- Name: uq_positions_company_org_job_title; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_positions_company_org_job_title ON public.positions USING btree (company_id, org_unit_id, job_catalog_id, position_title) WHERE (deleted_at IS NULL);


--
-- TOC entry 5541 (class 1259 OID 26895)
-- Name: uq_work_locations_company_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_work_locations_company_id_id ON public.work_locations USING btree (company_id, id);


--
-- TOC entry 5156 (class 1259 OID 16560)
-- Name: bname; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX bname ON storage.buckets USING btree (name);


--
-- TOC entry 5159 (class 1259 OID 16582)
-- Name: bucketid_objname; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX bucketid_objname ON storage.objects USING btree (bucket_id, name);


--
-- TOC entry 5171 (class 1259 OID 17339)
-- Name: idx_multipart_uploads_list; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_multipart_uploads_list ON storage.s3_multipart_uploads USING btree (bucket_id, key, created_at);


--
-- TOC entry 5160 (class 1259 OID 17399)
-- Name: idx_name_bucket_level_unique; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX idx_name_bucket_level_unique ON storage.objects USING btree (name COLLATE "C", bucket_id, level);


--
-- TOC entry 5161 (class 1259 OID 17304)
-- Name: idx_objects_bucket_id_name; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_bucket_id_name ON storage.objects USING btree (bucket_id, name COLLATE "C");


--
-- TOC entry 5162 (class 1259 OID 17405)
-- Name: idx_objects_lower_name; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_lower_name ON storage.objects USING btree ((path_tokens[level]), lower(name) text_pattern_ops, bucket_id, level);


--
-- TOC entry 5176 (class 1259 OID 17406)
-- Name: idx_prefixes_lower_name; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_prefixes_lower_name ON storage.prefixes USING btree (bucket_id, level, ((string_to_array(name, '/'::text))[level]), lower(name) text_pattern_ops);


--
-- TOC entry 5163 (class 1259 OID 16583)
-- Name: name_prefix_search; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX name_prefix_search ON storage.objects USING btree (name text_pattern_ops);


--
-- TOC entry 5164 (class 1259 OID 17403)
-- Name: objects_bucket_id_level_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX objects_bucket_id_level_idx ON storage.objects USING btree (bucket_id, level, name COLLATE "C");


--
-- TOC entry 6202 (class 2620 OID 36387)
-- Name: appraisal_competency_ratings t_lock_company_acr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_acr BEFORE UPDATE ON public.appraisal_competency_ratings FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6205 (class 2620 OID 36388)
-- Name: appraisal_goal_ratings t_lock_company_agr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_agr BEFORE UPDATE ON public.appraisal_goal_ratings FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6196 (class 2620 OID 36389)
-- Name: appraisal_template_competencies t_lock_company_atc; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_atc BEFORE UPDATE ON public.appraisal_template_competencies FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6243 (class 2620 OID 36999)
-- Name: attendance_exceptions t_lock_company_attendance_exceptions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_attendance_exceptions BEFORE UPDATE ON public.attendance_exceptions FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6247 (class 2620 OID 37001)
-- Name: attendance_qr_tokens t_lock_company_attendance_qr_tokens; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_attendance_qr_tokens BEFORE UPDATE ON public.attendance_qr_tokens FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6173 (class 2620 OID 36993)
-- Name: attendance_records t_lock_company_attendance_records; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_attendance_records BEFORE UPDATE ON public.attendance_records FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6239 (class 2620 OID 36997)
-- Name: attendance_rules t_lock_company_attendance_rules; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_attendance_rules BEFORE UPDATE ON public.attendance_rules FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6253 (class 2620 OID 36995)
-- Name: attendance_scan_logs t_lock_company_attendance_scan_logs; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_attendance_scan_logs BEFORE UPDATE ON public.attendance_scan_logs FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6218 (class 2620 OID 37005)
-- Name: employee_shift_assignments t_lock_company_employee_shift_assignments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_employee_shift_assignments BEFORE UPDATE ON public.employee_shift_assignments FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6231 (class 2620 OID 37003)
-- Name: employee_shifts t_lock_company_employee_shifts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_employee_shifts BEFORE UPDATE ON public.employee_shifts FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6227 (class 2620 OID 37007)
-- Name: employee_work_schedules t_lock_company_employee_work_schedules; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_employee_work_schedules BEFORE UPDATE ON public.employee_work_schedules FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6156 (class 2620 OID 36390)
-- Name: leave_approval_history t_lock_company_lah; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_lah BEFORE UPDATE ON public.leave_approval_history FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6150 (class 2620 OID 37013)
-- Name: leave_entitlements t_lock_company_leave_entitlements; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_leave_entitlements BEFORE UPDATE ON public.leave_entitlements FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6211 (class 2620 OID 37009)
-- Name: overtime_requests t_lock_company_overtime_requests; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_overtime_requests BEFORE UPDATE ON public.overtime_requests FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6164 (class 2620 OID 37011)
-- Name: payroll_items t_lock_company_payroll_items; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_payroll_items BEFORE UPDATE ON public.payroll_items FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6131 (class 2620 OID 36391)
-- Name: user_sessions t_lock_company_sess; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_lock_company_sess BEFORE UPDATE ON public.user_sessions FOR EACH ROW EXECUTE FUNCTION public.prevent_company_id_change();


--
-- TOC entry 6203 (class 2620 OID 36341)
-- Name: appraisal_competency_ratings t_set_company_acr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_acr BEFORE INSERT ON public.appraisal_competency_ratings FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6206 (class 2620 OID 36342)
-- Name: appraisal_goal_ratings t_set_company_agr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_agr BEFORE INSERT ON public.appraisal_goal_ratings FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6197 (class 2620 OID 36343)
-- Name: appraisal_template_competencies t_set_company_atc; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_atc BEFORE INSERT ON public.appraisal_template_competencies FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6244 (class 2620 OID 36998)
-- Name: attendance_exceptions t_set_company_attendance_exceptions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_attendance_exceptions BEFORE INSERT ON public.attendance_exceptions FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6248 (class 2620 OID 37000)
-- Name: attendance_qr_tokens t_set_company_attendance_qr_tokens; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_attendance_qr_tokens BEFORE INSERT ON public.attendance_qr_tokens FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6174 (class 2620 OID 36992)
-- Name: attendance_records t_set_company_attendance_records; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_attendance_records BEFORE INSERT ON public.attendance_records FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6240 (class 2620 OID 36996)
-- Name: attendance_rules t_set_company_attendance_rules; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_attendance_rules BEFORE INSERT ON public.attendance_rules FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6254 (class 2620 OID 36994)
-- Name: attendance_scan_logs t_set_company_attendance_scan_logs; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_attendance_scan_logs BEFORE INSERT ON public.attendance_scan_logs FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6219 (class 2620 OID 37004)
-- Name: employee_shift_assignments t_set_company_employee_shift_assignments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_employee_shift_assignments BEFORE INSERT ON public.employee_shift_assignments FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6232 (class 2620 OID 37002)
-- Name: employee_shifts t_set_company_employee_shifts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_employee_shifts BEFORE INSERT ON public.employee_shifts FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6228 (class 2620 OID 37006)
-- Name: employee_work_schedules t_set_company_employee_work_schedules; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_employee_work_schedules BEFORE INSERT ON public.employee_work_schedules FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6157 (class 2620 OID 36344)
-- Name: leave_approval_history t_set_company_lah; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_lah BEFORE INSERT ON public.leave_approval_history FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6151 (class 2620 OID 37012)
-- Name: leave_entitlements t_set_company_leave_entitlements; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_leave_entitlements BEFORE INSERT ON public.leave_entitlements FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6212 (class 2620 OID 37008)
-- Name: overtime_requests t_set_company_overtime_requests; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_overtime_requests BEFORE INSERT ON public.overtime_requests FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6165 (class 2620 OID 37010)
-- Name: payroll_items t_set_company_payroll_items; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_payroll_items BEFORE INSERT ON public.payroll_items FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6132 (class 2620 OID 36345)
-- Name: user_sessions t_set_company_sess; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER t_set_company_sess BEFORE INSERT ON public.user_sessions FOR EACH ROW EXECUTE FUNCTION public.set_tenant_company_id();


--
-- TOC entry 6266 (class 2620 OID 34661)
-- Name: approval_policy_assignments trg_ap_assign_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ap_assign_audit BEFORE INSERT OR UPDATE ON public.approval_policy_assignments FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6267 (class 2620 OID 34662)
-- Name: approval_policy_assignments trg_ap_assign_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ap_assign_touch BEFORE UPDATE ON public.approval_policy_assignments FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6263 (class 2620 OID 34630)
-- Name: approval_policy_levels trg_ap_levels_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ap_levels_audit BEFORE INSERT OR UPDATE ON public.approval_policy_levels FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6264 (class 2620 OID 34629)
-- Name: approval_policy_levels trg_ap_levels_set_company; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ap_levels_set_company BEFORE INSERT OR UPDATE ON public.approval_policy_levels FOR EACH ROW EXECUTE FUNCTION public.ap_levels_set_company_id();


--
-- TOC entry 6265 (class 2620 OID 34631)
-- Name: approval_policy_levels trg_ap_levels_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ap_levels_touch BEFORE UPDATE ON public.approval_policy_levels FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6261 (class 2620 OID 34601)
-- Name: approval_policies trg_ap_policies_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ap_policies_audit BEFORE INSERT OR UPDATE ON public.approval_policies FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6262 (class 2620 OID 34602)
-- Name: approval_policies trg_ap_policies_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ap_policies_touch BEFORE UPDATE ON public.approval_policies FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6208 (class 2620 OID 23716)
-- Name: appraisal_approvals trg_appraisal_approvals_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_appraisal_approvals_updated_at BEFORE UPDATE ON public.appraisal_approvals FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6209 (class 2620 OID 23717)
-- Name: appraisal_comments trg_appraisal_comments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_appraisal_comments_updated_at BEFORE UPDATE ON public.appraisal_comments FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6204 (class 2620 OID 23714)
-- Name: appraisal_competency_ratings trg_appraisal_competency_ratings_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_appraisal_competency_ratings_updated_at BEFORE UPDATE ON public.appraisal_competency_ratings FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6207 (class 2620 OID 23715)
-- Name: appraisal_goal_ratings trg_appraisal_goal_ratings_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_appraisal_goal_ratings_updated_at BEFORE UPDATE ON public.appraisal_goal_ratings FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6190 (class 2620 OID 23704)
-- Name: appraisal_periods trg_appraisal_periods_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_appraisal_periods_updated_at BEFORE UPDATE ON public.appraisal_periods FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6201 (class 2620 OID 23713)
-- Name: appraisal_reviews trg_appraisal_reviews_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_appraisal_reviews_updated_at BEFORE UPDATE ON public.appraisal_reviews FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6193 (class 2620 OID 23707)
-- Name: appraisal_templates trg_appraisal_templates_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_appraisal_templates_updated_at BEFORE UPDATE ON public.appraisal_templates FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6198 (class 2620 OID 23710)
-- Name: appraisals trg_appraisals_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_appraisals_updated_at BEFORE UPDATE ON public.appraisals FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6175 (class 2620 OID 32562)
-- Name: attendance_records trg_attendance_records_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_attendance_records_audit BEFORE INSERT OR UPDATE ON public.attendance_records FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6176 (class 2620 OID 32563)
-- Name: attendance_records trg_attendance_records_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_attendance_records_touch BEFORE UPDATE ON public.attendance_records FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6177 (class 2620 OID 22941)
-- Name: attendance_records trg_attendance_records_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_attendance_records_updated_at BEFORE UPDATE ON public.attendance_records FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6241 (class 2620 OID 32462)
-- Name: attendance_rules trg_attendance_rules_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_attendance_rules_audit BEFORE INSERT OR UPDATE ON public.attendance_rules FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6242 (class 2620 OID 32463)
-- Name: attendance_rules trg_attendance_rules_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_attendance_rules_touch BEFORE UPDATE ON public.attendance_rules FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6245 (class 2620 OID 32645)
-- Name: attendance_exceptions trg_attn_exc_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_attn_exc_audit BEFORE INSERT OR UPDATE ON public.attendance_exceptions FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6246 (class 2620 OID 32646)
-- Name: attendance_exceptions trg_attn_exc_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_attn_exc_touch BEFORE UPDATE ON public.attendance_exceptions FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6133 (class 2620 OID 24228)
-- Name: audit_logs trg_audit_logs_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_logs_audit BEFORE INSERT OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6182 (class 2620 OID 24217)
-- Name: claim_types trg_claim_types_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_claim_types_audit BEFORE INSERT OR UPDATE ON public.claim_types FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6183 (class 2620 OID 22946)
-- Name: claim_types trg_claim_types_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_claim_types_updated_at BEFORE UPDATE ON public.claim_types FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6127 (class 2620 OID 24201)
-- Name: companies trg_companies_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_companies_audit BEFORE INSERT OR UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6128 (class 2620 OID 17520)
-- Name: companies trg_companies_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_companies_updated_at BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6188 (class 2620 OID 24222)
-- Name: company_notification_settings trg_company_notification_settings_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_company_notification_settings_audit BEFORE INSERT OR UPDATE ON public.company_notification_settings FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6189 (class 2620 OID 22945)
-- Name: company_notification_settings trg_company_notification_settings_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_company_notification_settings_updated_at BEFORE UPDATE ON public.company_notification_settings FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6195 (class 2620 OID 23709)
-- Name: competencies trg_competencies_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_competencies_updated_at BEFORE UPDATE ON public.competencies FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6194 (class 2620 OID 23708)
-- Name: competency_categories trg_competency_categories_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_competency_categories_updated_at BEFORE UPDATE ON public.competency_categories FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6134 (class 2620 OID 24202)
-- Name: departments trg_departments_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_departments_audit BEFORE INSERT OR UPDATE ON public.departments FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6135 (class 2620 OID 18777)
-- Name: departments trg_departments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_departments_updated_at BEFORE UPDATE ON public.departments FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6237 (class 2620 OID 32383)
-- Name: device_register trg_device_register_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_device_register_audit BEFORE INSERT OR UPDATE ON public.device_register FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6238 (class 2620 OID 32384)
-- Name: device_register trg_device_register_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_device_register_touch BEFORE UPDATE ON public.device_register FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6144 (class 2620 OID 24210)
-- Name: employee_allowances trg_employee_allowances_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_allowances_audit BEFORE INSERT OR UPDATE ON public.employee_allowances FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6145 (class 2620 OID 19076)
-- Name: employee_allowances trg_employee_allowances_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_allowances_updated_at BEFORE UPDATE ON public.employee_allowances FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6184 (class 2620 OID 24218)
-- Name: employee_claims trg_employee_claims_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_claims_audit BEFORE INSERT OR UPDATE ON public.employee_claims FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6185 (class 2620 OID 22943)
-- Name: employee_claims trg_employee_claims_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_claims_updated_at BEFORE UPDATE ON public.employee_claims FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6146 (class 2620 OID 24211)
-- Name: employee_documents trg_employee_documents_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_documents_audit BEFORE INSERT OR UPDATE ON public.employee_documents FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6199 (class 2620 OID 23711)
-- Name: employee_goals trg_employee_goals_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_goals_updated_at BEFORE UPDATE ON public.employee_goals FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6147 (class 2620 OID 24212)
-- Name: employee_history trg_employee_history_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_history_audit BEFORE INSERT OR UPDATE ON public.employee_history FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6171 (class 2620 OID 24216)
-- Name: employee_loans trg_employee_loans_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_loans_audit BEFORE INSERT OR UPDATE ON public.employee_loans FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6172 (class 2620 OID 20258)
-- Name: employee_loans trg_employee_loans_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_loans_updated_at BEFORE UPDATE ON public.employee_loans FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6220 (class 2620 OID 24433)
-- Name: employee_shift_assignments trg_employee_shift_assignments_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_shift_assignments_audit BEFORE INSERT OR UPDATE ON public.employee_shift_assignments FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6221 (class 2620 OID 24432)
-- Name: employee_shift_assignments trg_employee_shift_assignments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_shift_assignments_updated_at BEFORE UPDATE ON public.employee_shift_assignments FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6233 (class 2620 OID 32243)
-- Name: employee_shifts trg_employee_shifts_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_shifts_audit BEFORE INSERT OR UPDATE ON public.employee_shifts FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6234 (class 2620 OID 32244)
-- Name: employee_shifts trg_employee_shifts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employee_shifts_updated_at BEFORE UPDATE ON public.employee_shifts FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6140 (class 2620 OID 24204)
-- Name: employees trg_employees_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employees_audit BEFORE INSERT OR UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6141 (class 2620 OID 35736)
-- Name: employees trg_employees_prevent_manager_cycle; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employees_prevent_manager_cycle BEFORE INSERT OR UPDATE OF manager_id ON public.employees FOR EACH ROW EXECUTE FUNCTION public.trg_employees_prevent_manager_cycle();


--
-- TOC entry 6142 (class 2620 OID 22940)
-- Name: employees trg_employees_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_employees_updated_at BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6168 (class 2620 OID 24224)
-- Name: epf_rates trg_epf_rates_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_epf_rates_audit BEFORE INSERT OR UPDATE ON public.epf_rates FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6235 (class 2620 OID 32313)
-- Name: geo_locations trg_geo_locations_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_geo_locations_audit BEFORE INSERT OR UPDATE ON public.geo_locations FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6236 (class 2620 OID 32314)
-- Name: geo_locations trg_geo_locations_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_geo_locations_touch BEFORE UPDATE ON public.geo_locations FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6200 (class 2620 OID 23712)
-- Name: goal_milestones trg_goal_milestones_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_goal_milestones_updated_at BEFORE UPDATE ON public.goal_milestones FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6259 (class 2620 OID 34125)
-- Name: headcount_plans trg_hc_plan_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hc_plan_audit BEFORE INSERT OR UPDATE ON public.headcount_plans FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6260 (class 2620 OID 34126)
-- Name: headcount_plans trg_hc_plan_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hc_plan_touch BEFORE UPDATE ON public.headcount_plans FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6270 (class 2620 OID 34862)
-- Name: headcount_approvals trg_hreq_appr_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hreq_appr_audit BEFORE INSERT OR UPDATE ON public.headcount_approvals FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6271 (class 2620 OID 35584)
-- Name: headcount_approvals trg_hreq_appr_log_event; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hreq_appr_log_event AFTER INSERT OR UPDATE ON public.headcount_approvals FOR EACH ROW EXECUTE FUNCTION public.trg_log_event_hreq();


--
-- TOC entry 6272 (class 2620 OID 34861)
-- Name: headcount_approvals trg_hreq_appr_set_company; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hreq_appr_set_company BEFORE INSERT OR UPDATE ON public.headcount_approvals FOR EACH ROW EXECUTE FUNCTION public.hreq_appr_set_company_id();


--
-- TOC entry 6273 (class 2620 OID 34863)
-- Name: headcount_approvals trg_hreq_appr_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hreq_appr_touch BEFORE UPDATE ON public.headcount_approvals FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6268 (class 2620 OID 34794)
-- Name: headcount_requests trg_hreq_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hreq_audit BEFORE INSERT OR UPDATE ON public.headcount_requests FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6269 (class 2620 OID 34795)
-- Name: headcount_requests trg_hreq_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_hreq_touch BEFORE UPDATE ON public.headcount_requests FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6276 (class 2620 OID 35032)
-- Name: job_requisition_approvals trg_jreq_appr_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_jreq_appr_audit BEFORE INSERT OR UPDATE ON public.job_requisition_approvals FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6277 (class 2620 OID 35586)
-- Name: job_requisition_approvals trg_jreq_appr_log_event; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_jreq_appr_log_event AFTER INSERT OR UPDATE ON public.job_requisition_approvals FOR EACH ROW EXECUTE FUNCTION public.trg_log_event_jreq();


--
-- TOC entry 6278 (class 2620 OID 35031)
-- Name: job_requisition_approvals trg_jreq_appr_set_company; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_jreq_appr_set_company BEFORE INSERT OR UPDATE ON public.job_requisition_approvals FOR EACH ROW EXECUTE FUNCTION public.jreq_appr_set_company_id();


--
-- TOC entry 6279 (class 2620 OID 35033)
-- Name: job_requisition_approvals trg_jreq_appr_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_jreq_appr_touch BEFORE UPDATE ON public.job_requisition_approvals FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6274 (class 2620 OID 34963)
-- Name: job_requisitions trg_jreq_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_jreq_audit BEFORE INSERT OR UPDATE ON public.job_requisitions FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6275 (class 2620 OID 34964)
-- Name: job_requisitions trg_jreq_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_jreq_touch BEFORE UPDATE ON public.job_requisitions FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6251 (class 2620 OID 32879)
-- Name: kiosk_sessions trg_kiosk_sessions_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_kiosk_sessions_audit BEFORE INSERT OR UPDATE ON public.kiosk_sessions FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6252 (class 2620 OID 32880)
-- Name: kiosk_sessions trg_kiosk_sessions_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_kiosk_sessions_touch BEFORE UPDATE ON public.kiosk_sessions FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6154 (class 2620 OID 24207)
-- Name: leave_applications trg_leave_applications_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_applications_audit BEFORE INSERT OR UPDATE ON public.leave_applications FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6155 (class 2620 OID 19743)
-- Name: leave_applications trg_leave_applications_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_applications_updated_at BEFORE UPDATE ON public.leave_applications FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6159 (class 2620 OID 24209)
-- Name: leave_balance_adjustments trg_leave_balance_adjustments_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_balance_adjustments_audit BEFORE INSERT OR UPDATE ON public.leave_balance_adjustments FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6158 (class 2620 OID 24208)
-- Name: leave_blackout_periods trg_leave_blackout_periods_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_blackout_periods_audit BEFORE INSERT OR UPDATE ON public.leave_blackout_periods FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6152 (class 2620 OID 24206)
-- Name: leave_entitlements trg_leave_entitlements_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_entitlements_audit BEFORE INSERT OR UPDATE ON public.leave_entitlements FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6153 (class 2620 OID 19634)
-- Name: leave_entitlements trg_leave_entitlements_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_entitlements_updated_at BEFORE UPDATE ON public.leave_entitlements FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6148 (class 2620 OID 24205)
-- Name: leave_types trg_leave_types_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_types_audit BEFORE INSERT OR UPDATE ON public.leave_types FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6149 (class 2620 OID 19556)
-- Name: leave_types trg_leave_types_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_types_updated_at BEFORE UPDATE ON public.leave_types FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6222 (class 2620 OID 28813)
-- Name: gl_journal_headers trg_lock_posted_header_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lock_posted_header_upd BEFORE UPDATE ON public.gl_journal_headers FOR EACH ROW EXECUTE FUNCTION public.prevent_change_if_posted_header();


--
-- TOC entry 6224 (class 2620 OID 28817)
-- Name: gl_journal_lines trg_lock_posted_lines_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lock_posted_lines_del BEFORE DELETE ON public.gl_journal_lines FOR EACH ROW EXECUTE FUNCTION public.prevent_change_if_posted_lines();


--
-- TOC entry 6225 (class 2620 OID 28815)
-- Name: gl_journal_lines trg_lock_posted_lines_ins; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lock_posted_lines_ins BEFORE INSERT ON public.gl_journal_lines FOR EACH ROW EXECUTE FUNCTION public.prevent_change_if_posted_lines();


--
-- TOC entry 6226 (class 2620 OID 28816)
-- Name: gl_journal_lines trg_lock_posted_lines_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_lock_posted_lines_upd BEFORE UPDATE ON public.gl_journal_lines FOR EACH ROW EXECUTE FUNCTION public.prevent_change_if_posted_lines();


--
-- TOC entry 6129 (class 2620 OID 36767)
-- Name: companies trg_maintain_company_links; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_maintain_company_links AFTER INSERT OR UPDATE OF parent_company_id ON public.companies FOR EACH ROW EXECUTE FUNCTION public.maintain_company_links();


--
-- TOC entry 6186 (class 2620 OID 24223)
-- Name: notification_queue trg_notification_queue_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notification_queue_audit BEFORE INSERT OR UPDATE ON public.notification_queue FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6187 (class 2620 OID 22944)
-- Name: notification_queue trg_notification_queue_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notification_queue_updated_at BEFORE UPDATE ON public.notification_queue FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6161 (class 2620 OID 27870)
-- Name: payroll_batches trg_on_payroll_approved; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_on_payroll_approved AFTER UPDATE ON public.payroll_batches FOR EACH ROW EXECUTE FUNCTION public.on_payroll_approved();


--
-- TOC entry 6178 (class 2620 OID 35582)
-- Name: overtime_approvals trg_ot_approvals_log_event; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ot_approvals_log_event AFTER INSERT OR UPDATE ON public.overtime_approvals FOR EACH ROW EXECUTE FUNCTION public.trg_log_event_ot();


--
-- TOC entry 6179 (class 2620 OID 35508)
-- Name: overtime_approvals trg_ot_approvals_sync_status_text; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ot_approvals_sync_status_text BEFORE INSERT OR UPDATE ON public.overtime_approvals FOR EACH ROW EXECUTE FUNCTION public.ot_approvals_sync_status_text();


--
-- TOC entry 6180 (class 2620 OID 24221)
-- Name: overtime_approvals trg_overtime_approvals_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_overtime_approvals_audit BEFORE INSERT OR UPDATE ON public.overtime_approvals FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6181 (class 2620 OID 22942)
-- Name: overtime_approvals trg_overtime_approvals_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_overtime_approvals_updated_at BEFORE UPDATE ON public.overtime_approvals FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6213 (class 2620 OID 24220)
-- Name: overtime_requests trg_overtime_requests_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_overtime_requests_audit BEFORE INSERT OR UPDATE ON public.overtime_requests FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6162 (class 2620 OID 24213)
-- Name: payroll_batches trg_payroll_batches_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_batches_audit BEFORE INSERT OR UPDATE ON public.payroll_batches FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6163 (class 2620 OID 20031)
-- Name: payroll_batches trg_payroll_batches_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_batches_updated_at BEFORE UPDATE ON public.payroll_batches FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6166 (class 2620 OID 24214)
-- Name: payroll_items trg_payroll_items_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_items_audit BEFORE INSERT OR UPDATE ON public.payroll_items FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6167 (class 2620 OID 20135)
-- Name: payroll_items trg_payroll_items_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_items_updated_at BEFORE UPDATE ON public.payroll_items FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6170 (class 2620 OID 24226)
-- Name: pcb_tax_schedules trg_pcb_tax_schedules_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pcb_tax_schedules_audit BEFORE INSERT OR UPDATE ON public.pcb_tax_schedules FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6256 (class 2620 OID 34049)
-- Name: position_assignments trg_pos_assign_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pos_assign_audit BEFORE INSERT OR UPDATE ON public.position_assignments FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6257 (class 2620 OID 34276)
-- Name: position_assignments trg_pos_assign_history; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pos_assign_history AFTER INSERT OR DELETE OR UPDATE ON public.position_assignments FOR EACH ROW EXECUTE FUNCTION public.trg_pos_assign_history_fn();


--
-- TOC entry 6258 (class 2620 OID 34050)
-- Name: position_assignments trg_pos_assign_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pos_assign_touch BEFORE UPDATE ON public.position_assignments FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6136 (class 2620 OID 33270)
-- Name: positions trg_positions_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_positions_audit BEFORE INSERT OR UPDATE ON public.positions FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6137 (class 2620 OID 34274)
-- Name: positions trg_positions_history; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_positions_history AFTER INSERT OR DELETE OR UPDATE ON public.positions FOR EACH ROW EXECUTE FUNCTION public.trg_positions_history_fn();


--
-- TOC entry 6138 (class 2620 OID 33271)
-- Name: positions trg_positions_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_positions_touch BEFORE UPDATE ON public.positions FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6139 (class 2620 OID 18854)
-- Name: positions trg_positions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_positions_updated_at BEFORE UPDATE ON public.positions FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6160 (class 2620 OID 24215)
-- Name: public_holidays trg_public_holidays_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_public_holidays_audit BEFORE INSERT OR UPDATE ON public.public_holidays FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6249 (class 2620 OID 32804)
-- Name: attendance_qr_tokens trg_qr_tokens_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_qr_tokens_audit BEFORE INSERT OR UPDATE ON public.attendance_qr_tokens FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6250 (class 2620 OID 32805)
-- Name: attendance_qr_tokens trg_qr_tokens_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_qr_tokens_touch BEFORE UPDATE ON public.attendance_qr_tokens FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6192 (class 2620 OID 23706)
-- Name: rating_scale_values trg_rating_scale_values_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_rating_scale_values_updated_at BEFORE UPDATE ON public.rating_scale_values FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6191 (class 2620 OID 23705)
-- Name: rating_scales trg_rating_scales_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_rating_scales_updated_at BEFORE UPDATE ON public.rating_scales FOR EACH ROW EXECUTE FUNCTION public.update_appraisal_updated_at();


--
-- TOC entry 6255 (class 2620 OID 33067)
-- Name: attendance_scan_logs trg_scan_logs_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_scan_logs_audit BEFORE INSERT ON public.attendance_scan_logs FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6143 (class 2620 OID 27080)
-- Name: employees trg_set_employee_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_employee_number BEFORE INSERT ON public.employees FOR EACH ROW EXECUTE FUNCTION public.set_employee_number();


--
-- TOC entry 6223 (class 2620 OID 28116)
-- Name: gl_journal_headers trg_set_journal_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_journal_number BEFORE INSERT ON public.gl_journal_headers FOR EACH ROW EXECUTE FUNCTION public.set_journal_number();


--
-- TOC entry 6216 (class 2620 OID 24431)
-- Name: shift_templates trg_shift_templates_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shift_templates_audit BEFORE INSERT OR UPDATE ON public.shift_templates FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6217 (class 2620 OID 24430)
-- Name: shift_templates trg_shift_templates_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shift_templates_updated_at BEFORE UPDATE ON public.shift_templates FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6169 (class 2620 OID 24225)
-- Name: socso_contribution_rates trg_socso_contribution_rates_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_socso_contribution_rates_audit BEFORE INSERT OR UPDATE ON public.socso_contribution_rates FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6126 (class 2620 OID 17489)
-- Name: subscription_plans trg_subscription_plans_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_subscription_plans_updated_at BEFORE UPDATE ON public.subscription_plans FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6130 (class 2620 OID 17555)
-- Name: users trg_users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6214 (class 2620 OID 24429)
-- Name: work_locations trg_work_locations_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_work_locations_audit BEFORE INSERT OR UPDATE ON public.work_locations FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6215 (class 2620 OID 24428)
-- Name: work_locations trg_work_locations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_work_locations_updated_at BEFORE UPDATE ON public.work_locations FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6229 (class 2620 OID 31973)
-- Name: work_schedules trg_work_schedules_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_work_schedules_audit BEFORE INSERT OR UPDATE ON public.work_schedules FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6230 (class 2620 OID 31974)
-- Name: work_schedules trg_work_schedules_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_work_schedules_updated_at BEFORE UPDATE ON public.work_schedules FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();


--
-- TOC entry 6210 (class 2620 OID 24227)
-- Name: zakat_rates trg_zakat_rates_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_zakat_rates_audit BEFORE INSERT OR UPDATE ON public.zakat_rates FOR EACH ROW EXECUTE FUNCTION public.set_audit_fields();


--
-- TOC entry 6119 (class 2620 OID 17413)
-- Name: buckets enforce_bucket_name_length_trigger; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();


--
-- TOC entry 6120 (class 2620 OID 17444)
-- Name: objects objects_delete_delete_prefix; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER objects_delete_delete_prefix AFTER DELETE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.delete_prefix_hierarchy_trigger();


--
-- TOC entry 6121 (class 2620 OID 17394)
-- Name: objects objects_insert_create_prefix; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER objects_insert_create_prefix BEFORE INSERT ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.objects_insert_prefix_trigger();


--
-- TOC entry 6122 (class 2620 OID 17443)
-- Name: objects objects_update_create_prefix; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER objects_update_create_prefix BEFORE UPDATE ON storage.objects FOR EACH ROW WHEN (((new.name <> old.name) OR (new.bucket_id <> old.bucket_id))) EXECUTE FUNCTION storage.objects_update_prefix_trigger();


--
-- TOC entry 6124 (class 2620 OID 17409)
-- Name: prefixes prefixes_create_hierarchy; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER prefixes_create_hierarchy BEFORE INSERT ON storage.prefixes FOR EACH ROW WHEN ((pg_trigger_depth() < 1)) EXECUTE FUNCTION storage.prefixes_insert_trigger();


--
-- TOC entry 6125 (class 2620 OID 17445)
-- Name: prefixes prefixes_delete_hierarchy; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER prefixes_delete_hierarchy AFTER DELETE ON storage.prefixes FOR EACH ROW EXECUTE FUNCTION storage.delete_prefix_hierarchy_trigger();


--
-- TOC entry 6123 (class 2620 OID 17286)
-- Name: objects update_objects_updated_at; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();


--
-- TOC entry 5974 (class 2606 OID 23603)
-- Name: appraisal_approvals appraisal_approvals_appraisal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_approvals
    ADD CONSTRAINT appraisal_approvals_appraisal_id_fkey FOREIGN KEY (appraisal_id) REFERENCES public.appraisals(id) ON DELETE CASCADE;


--
-- TOC entry 5975 (class 2606 OID 23608)
-- Name: appraisal_approvals appraisal_approvals_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_approvals
    ADD CONSTRAINT appraisal_approvals_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES public.users(id);


--
-- TOC entry 5976 (class 2606 OID 23598)
-- Name: appraisal_approvals appraisal_approvals_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_approvals
    ADD CONSTRAINT appraisal_approvals_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5980 (class 2606 OID 23658)
-- Name: appraisal_comments appraisal_comments_appraisal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_comments
    ADD CONSTRAINT appraisal_comments_appraisal_id_fkey FOREIGN KEY (appraisal_id) REFERENCES public.appraisals(id) ON DELETE CASCADE;


--
-- TOC entry 5981 (class 2606 OID 23653)
-- Name: appraisal_comments appraisal_comments_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_comments
    ADD CONSTRAINT appraisal_comments_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5982 (class 2606 OID 23668)
-- Name: appraisal_comments appraisal_comments_parent_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_comments
    ADD CONSTRAINT appraisal_comments_parent_comment_id_fkey FOREIGN KEY (parent_comment_id) REFERENCES public.appraisal_comments(id);


--
-- TOC entry 5983 (class 2606 OID 23663)
-- Name: appraisal_comments appraisal_comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_comments
    ADD CONSTRAINT appraisal_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- TOC entry 5968 (class 2606 OID 23555)
-- Name: appraisal_competency_ratings appraisal_competency_ratings_competency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_competency_ratings
    ADD CONSTRAINT appraisal_competency_ratings_competency_id_fkey FOREIGN KEY (competency_id) REFERENCES public.competencies(id);


--
-- TOC entry 5969 (class 2606 OID 23550)
-- Name: appraisal_competency_ratings appraisal_competency_ratings_review_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_competency_ratings
    ADD CONSTRAINT appraisal_competency_ratings_review_id_fkey FOREIGN KEY (review_id) REFERENCES public.appraisal_reviews(id) ON DELETE CASCADE;


--
-- TOC entry 5977 (class 2606 OID 23630)
-- Name: appraisal_documents appraisal_documents_appraisal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_documents
    ADD CONSTRAINT appraisal_documents_appraisal_id_fkey FOREIGN KEY (appraisal_id) REFERENCES public.appraisals(id) ON DELETE CASCADE;


--
-- TOC entry 5978 (class 2606 OID 23625)
-- Name: appraisal_documents appraisal_documents_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_documents
    ADD CONSTRAINT appraisal_documents_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5979 (class 2606 OID 23635)
-- Name: appraisal_documents appraisal_documents_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_documents
    ADD CONSTRAINT appraisal_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id);


--
-- TOC entry 5971 (class 2606 OID 23580)
-- Name: appraisal_goal_ratings appraisal_goal_ratings_goal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_goal_ratings
    ADD CONSTRAINT appraisal_goal_ratings_goal_id_fkey FOREIGN KEY (goal_id) REFERENCES public.employee_goals(id);


--
-- TOC entry 5972 (class 2606 OID 23575)
-- Name: appraisal_goal_ratings appraisal_goal_ratings_review_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_goal_ratings
    ADD CONSTRAINT appraisal_goal_ratings_review_id_fkey FOREIGN KEY (review_id) REFERENCES public.appraisal_reviews(id) ON DELETE CASCADE;


--
-- TOC entry 5984 (class 2606 OID 23690)
-- Name: appraisal_history appraisal_history_appraisal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_history
    ADD CONSTRAINT appraisal_history_appraisal_id_fkey FOREIGN KEY (appraisal_id) REFERENCES public.appraisals(id) ON DELETE CASCADE;


--
-- TOC entry 5985 (class 2606 OID 23695)
-- Name: appraisal_history appraisal_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_history
    ADD CONSTRAINT appraisal_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);


--
-- TOC entry 5986 (class 2606 OID 23685)
-- Name: appraisal_history appraisal_history_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_history
    ADD CONSTRAINT appraisal_history_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5932 (class 2606 OID 23195)
-- Name: appraisal_periods appraisal_periods_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_periods
    ADD CONSTRAINT appraisal_periods_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5933 (class 2606 OID 23200)
-- Name: appraisal_periods appraisal_periods_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_periods
    ADD CONSTRAINT appraisal_periods_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5934 (class 2606 OID 23205)
-- Name: appraisal_periods appraisal_periods_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_periods
    ADD CONSTRAINT appraisal_periods_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5965 (class 2606 OID 23524)
-- Name: appraisal_reviews appraisal_reviews_appraisal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_reviews
    ADD CONSTRAINT appraisal_reviews_appraisal_id_fkey FOREIGN KEY (appraisal_id) REFERENCES public.appraisals(id) ON DELETE CASCADE;


--
-- TOC entry 5966 (class 2606 OID 23519)
-- Name: appraisal_reviews appraisal_reviews_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_reviews
    ADD CONSTRAINT appraisal_reviews_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5967 (class 2606 OID 23529)
-- Name: appraisal_reviews appraisal_reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_reviews
    ADD CONSTRAINT appraisal_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.employees(id);


--
-- TOC entry 5946 (class 2606 OID 23366)
-- Name: appraisal_template_competencies appraisal_template_competencies_competency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_template_competencies
    ADD CONSTRAINT appraisal_template_competencies_competency_id_fkey FOREIGN KEY (competency_id) REFERENCES public.competencies(id) ON DELETE CASCADE;


--
-- TOC entry 5947 (class 2606 OID 23361)
-- Name: appraisal_template_competencies appraisal_template_competencies_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_template_competencies
    ADD CONSTRAINT appraisal_template_competencies_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.appraisal_templates(id) ON DELETE CASCADE;


--
-- TOC entry 5939 (class 2606 OID 23281)
-- Name: appraisal_templates appraisal_templates_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_templates
    ADD CONSTRAINT appraisal_templates_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5940 (class 2606 OID 23291)
-- Name: appraisal_templates appraisal_templates_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_templates
    ADD CONSTRAINT appraisal_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5941 (class 2606 OID 23286)
-- Name: appraisal_templates appraisal_templates_rating_scale_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_templates
    ADD CONSTRAINT appraisal_templates_rating_scale_id_fkey FOREIGN KEY (rating_scale_id) REFERENCES public.rating_scales(id);


--
-- TOC entry 5942 (class 2606 OID 23296)
-- Name: appraisal_templates appraisal_templates_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_templates
    ADD CONSTRAINT appraisal_templates_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5949 (class 2606 OID 23412)
-- Name: appraisals appraisals_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisals
    ADD CONSTRAINT appraisals_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id);


--
-- TOC entry 5950 (class 2606 OID 23387)
-- Name: appraisals appraisals_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisals
    ADD CONSTRAINT appraisals_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5951 (class 2606 OID 23417)
-- Name: appraisals appraisals_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisals
    ADD CONSTRAINT appraisals_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5952 (class 2606 OID 23392)
-- Name: appraisals appraisals_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisals
    ADD CONSTRAINT appraisals_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5953 (class 2606 OID 23397)
-- Name: appraisals appraisals_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisals
    ADD CONSTRAINT appraisals_period_id_fkey FOREIGN KEY (period_id) REFERENCES public.appraisal_periods(id) ON DELETE CASCADE;


--
-- TOC entry 5954 (class 2606 OID 23407)
-- Name: appraisals appraisals_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisals
    ADD CONSTRAINT appraisals_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.employees(id);


--
-- TOC entry 5955 (class 2606 OID 23402)
-- Name: appraisals appraisals_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisals
    ADD CONSTRAINT appraisals_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.appraisal_templates(id);


--
-- TOC entry 5956 (class 2606 OID 23422)
-- Name: appraisals appraisals_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisals
    ADD CONSTRAINT appraisals_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6113 (class 2606 OID 35131)
-- Name: approval_function_tags approval_function_tags_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_function_tags
    ADD CONSTRAINT approval_function_tags_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6095 (class 2606 OID 34593)
-- Name: approval_policies approval_policies_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_policies
    ADD CONSTRAINT approval_policies_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6097 (class 2606 OID 34648)
-- Name: approval_policy_assignments approval_policy_assignments_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_policy_assignments
    ADD CONSTRAINT approval_policy_assignments_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6098 (class 2606 OID 34653)
-- Name: approval_policy_assignments approval_policy_assignments_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_policy_assignments
    ADD CONSTRAINT approval_policy_assignments_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.approval_policies(id) ON DELETE CASCADE;


--
-- TOC entry 6096 (class 2606 OID 34618)
-- Name: approval_policy_levels approval_policy_levels_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_policy_levels
    ADD CONSTRAINT approval_policy_levels_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.approval_policies(id) ON DELETE CASCADE;


--
-- TOC entry 6074 (class 2606 OID 32634)
-- Name: attendance_exceptions attendance_exceptions_attendance_record_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_exceptions
    ADD CONSTRAINT attendance_exceptions_attendance_record_id_fkey FOREIGN KEY (attendance_record_id) REFERENCES public.attendance_records(id) ON DELETE SET NULL;


--
-- TOC entry 6075 (class 2606 OID 32624)
-- Name: attendance_exceptions attendance_exceptions_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_exceptions
    ADD CONSTRAINT attendance_exceptions_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6076 (class 2606 OID 32629)
-- Name: attendance_exceptions attendance_exceptions_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_exceptions
    ADD CONSTRAINT attendance_exceptions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6077 (class 2606 OID 32791)
-- Name: attendance_qr_tokens attendance_qr_tokens_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_qr_tokens
    ADD CONSTRAINT attendance_qr_tokens_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6078 (class 2606 OID 32796)
-- Name: attendance_qr_tokens attendance_qr_tokens_geo_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_qr_tokens
    ADD CONSTRAINT attendance_qr_tokens_geo_location_id_fkey FOREIGN KEY (geo_location_id) REFERENCES public.geo_locations(id) ON DELETE SET NULL;


--
-- TOC entry 5898 (class 2606 OID 22071)
-- Name: attendance_records attendance_records_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5899 (class 2606 OID 22081)
-- Name: attendance_records attendance_records_created_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5900 (class 2606 OID 22076)
-- Name: attendance_records attendance_records_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5901 (class 2606 OID 22086)
-- Name: attendance_records attendance_records_updated_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT attendance_records_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 6072 (class 2606 OID 32450)
-- Name: attendance_rules attendance_rules_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_rules
    ADD CONSTRAINT attendance_rules_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6073 (class 2606 OID 32455)
-- Name: attendance_rules attendance_rules_default_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_rules
    ADD CONSTRAINT attendance_rules_default_location_id_fkey FOREIGN KEY (default_location_id) REFERENCES public.geo_locations(id) ON DELETE SET NULL;


--
-- TOC entry 6082 (class 2606 OID 33032)
-- Name: attendance_scan_logs attendance_scan_logs_attendance_record_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_scan_logs
    ADD CONSTRAINT attendance_scan_logs_attendance_record_id_fkey FOREIGN KEY (attendance_record_id) REFERENCES public.attendance_records(id) ON DELETE SET NULL;


--
-- TOC entry 6083 (class 2606 OID 33022)
-- Name: attendance_scan_logs attendance_scan_logs_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_scan_logs
    ADD CONSTRAINT attendance_scan_logs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6084 (class 2606 OID 33037)
-- Name: attendance_scan_logs attendance_scan_logs_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_scan_logs
    ADD CONSTRAINT attendance_scan_logs_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.device_register(id) ON DELETE SET NULL;


--
-- TOC entry 6085 (class 2606 OID 33027)
-- Name: attendance_scan_logs attendance_scan_logs_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_scan_logs
    ADD CONSTRAINT attendance_scan_logs_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 6086 (class 2606 OID 33052)
-- Name: attendance_scan_logs attendance_scan_logs_geo_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_scan_logs
    ADD CONSTRAINT attendance_scan_logs_geo_location_id_fkey FOREIGN KEY (geo_location_id) REFERENCES public.geo_locations(id) ON DELETE SET NULL;


--
-- TOC entry 6087 (class 2606 OID 33047)
-- Name: attendance_scan_logs attendance_scan_logs_kiosk_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_scan_logs
    ADD CONSTRAINT attendance_scan_logs_kiosk_session_id_fkey FOREIGN KEY (kiosk_session_id) REFERENCES public.kiosk_sessions(id) ON DELETE SET NULL;


--
-- TOC entry 6088 (class 2606 OID 33042)
-- Name: attendance_scan_logs attendance_scan_logs_qr_token_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_scan_logs
    ADD CONSTRAINT attendance_scan_logs_qr_token_id_fkey FOREIGN KEY (qr_token_id) REFERENCES public.attendance_qr_tokens(id) ON DELETE SET NULL;


--
-- TOC entry 5802 (class 2606 OID 17584)
-- Name: audit_logs audit_logs_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5803 (class 2606 OID 23922)
-- Name: audit_logs audit_logs_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5804 (class 2606 OID 23927)
-- Name: audit_logs audit_logs_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5805 (class 2606 OID 17589)
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- TOC entry 5915 (class 2606 OID 22190)
-- Name: claim_types claim_types_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_types
    ADD CONSTRAINT claim_types_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5916 (class 2606 OID 22195)
-- Name: claim_types claim_types_created_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_types
    ADD CONSTRAINT claim_types_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5917 (class 2606 OID 22200)
-- Name: claim_types claim_types_updated_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.claim_types
    ADD CONSTRAINT claim_types_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5793 (class 2606 OID 23862)
-- Name: companies companies_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5794 (class 2606 OID 17513)
-- Name: companies companies_subscription_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_subscription_plan_id_fkey FOREIGN KEY (subscription_plan_id) REFERENCES public.subscription_plans(id);


--
-- TOC entry 5795 (class 2606 OID 23867)
-- Name: companies companies_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6012 (class 2606 OID 27985)
-- Name: company_journal_sequences company_journal_sequences_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_journal_sequences
    ADD CONSTRAINT company_journal_sequences_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5929 (class 2606 OID 22376)
-- Name: company_notification_settings company_notification_settings_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_notification_settings
    ADD CONSTRAINT company_notification_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5930 (class 2606 OID 22381)
-- Name: company_notification_settings company_notification_settings_created_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_notification_settings
    ADD CONSTRAINT company_notification_settings_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5931 (class 2606 OID 22386)
-- Name: company_notification_settings company_notification_settings_updated_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_notification_settings
    ADD CONSTRAINT company_notification_settings_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5998 (class 2606 OID 26951)
-- Name: company_sequences company_sequences_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_sequences
    ADD CONSTRAINT company_sequences_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5944 (class 2606 OID 23342)
-- Name: competencies competencies_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competencies
    ADD CONSTRAINT competencies_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.competency_categories(id) ON DELETE SET NULL;


--
-- TOC entry 5945 (class 2606 OID 23337)
-- Name: competencies competencies_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competencies
    ADD CONSTRAINT competencies_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5943 (class 2606 OID 23317)
-- Name: competency_categories competency_categories_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competency_categories
    ADD CONSTRAINT competency_categories_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5997 (class 2606 OID 26722)
-- Name: cost_centers cost_centers_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cost_centers
    ADD CONSTRAINT cost_centers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5806 (class 2606 OID 24229)
-- Name: departments departments_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5807 (class 2606 OID 18763)
-- Name: departments departments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5808 (class 2606 OID 18758)
-- Name: departments departments_parent_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_parent_department_id_fkey FOREIGN KEY (parent_department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- TOC entry 5809 (class 2606 OID 18768)
-- Name: departments departments_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6070 (class 2606 OID 32369)
-- Name: device_register device_register_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_register
    ADD CONSTRAINT device_register_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6071 (class 2606 OID 32374)
-- Name: device_register device_register_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_register
    ADD CONSTRAINT device_register_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 6013 (class 2606 OID 29249)
-- Name: employee_actions employee_actions_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_actions
    ADD CONSTRAINT employee_actions_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6014 (class 2606 OID 29254)
-- Name: employee_actions employee_actions_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_actions
    ADD CONSTRAINT employee_actions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6021 (class 2606 OID 29395)
-- Name: employee_addresses employee_addresses_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_addresses
    ADD CONSTRAINT employee_addresses_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6022 (class 2606 OID 29400)
-- Name: employee_addresses employee_addresses_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_addresses
    ADD CONSTRAINT employee_addresses_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5826 (class 2606 OID 19053)
-- Name: employee_allowances employee_allowances_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_allowances
    ADD CONSTRAINT employee_allowances_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5827 (class 2606 OID 19063)
-- Name: employee_allowances employee_allowances_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_allowances
    ADD CONSTRAINT employee_allowances_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5828 (class 2606 OID 19058)
-- Name: employee_allowances employee_allowances_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_allowances
    ADD CONSTRAINT employee_allowances_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5829 (class 2606 OID 19068)
-- Name: employee_allowances employee_allowances_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_allowances
    ADD CONSTRAINT employee_allowances_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6027 (class 2606 OID 29620)
-- Name: employee_bank_accounts employee_bank_accounts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_bank_accounts
    ADD CONSTRAINT employee_bank_accounts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6028 (class 2606 OID 29625)
-- Name: employee_bank_accounts employee_bank_accounts_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_bank_accounts
    ADD CONSTRAINT employee_bank_accounts_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5918 (class 2606 OID 22246)
-- Name: employee_claims employee_claims_approver_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_claims
    ADD CONSTRAINT employee_claims_approver_fk FOREIGN KEY (approver_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5919 (class 2606 OID 22231)
-- Name: employee_claims employee_claims_claim_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_claims
    ADD CONSTRAINT employee_claims_claim_type_id_fkey FOREIGN KEY (claim_type_id) REFERENCES public.claim_types(id) ON DELETE RESTRICT;


--
-- TOC entry 5920 (class 2606 OID 22221)
-- Name: employee_claims employee_claims_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_claims
    ADD CONSTRAINT employee_claims_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5921 (class 2606 OID 22236)
-- Name: employee_claims employee_claims_created_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_claims
    ADD CONSTRAINT employee_claims_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5922 (class 2606 OID 22226)
-- Name: employee_claims employee_claims_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_claims
    ADD CONSTRAINT employee_claims_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5923 (class 2606 OID 22241)
-- Name: employee_claims employee_claims_updated_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_claims
    ADD CONSTRAINT employee_claims_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 6025 (class 2606 OID 29536)
-- Name: employee_compensation employee_compensation_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_compensation
    ADD CONSTRAINT employee_compensation_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6026 (class 2606 OID 29541)
-- Name: employee_compensation employee_compensation_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_compensation
    ADD CONSTRAINT employee_compensation_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5830 (class 2606 OID 19155)
-- Name: employee_documents employee_documents_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5831 (class 2606 OID 23892)
-- Name: employee_documents employee_documents_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5832 (class 2606 OID 19160)
-- Name: employee_documents employee_documents_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5833 (class 2606 OID 23897)
-- Name: employee_documents employee_documents_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5834 (class 2606 OID 19165)
-- Name: employee_documents employee_documents_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id);


--
-- TOC entry 6114 (class 2606 OID 35827)
-- Name: employee_function_memberships employee_function_memberships_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_function_memberships
    ADD CONSTRAINT employee_function_memberships_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6115 (class 2606 OID 35832)
-- Name: employee_function_memberships employee_function_memberships_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_function_memberships
    ADD CONSTRAINT employee_function_memberships_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6116 (class 2606 OID 35837)
-- Name: employee_function_memberships employee_function_memberships_function_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_function_memberships
    ADD CONSTRAINT employee_function_memberships_function_tag_id_fkey FOREIGN KEY (function_tag_id) REFERENCES public.approval_function_tags(id) ON DELETE CASCADE;


--
-- TOC entry 5957 (class 2606 OID 23457)
-- Name: employee_goals employee_goals_appraisal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_appraisal_id_fkey FOREIGN KEY (appraisal_id) REFERENCES public.appraisals(id) ON DELETE SET NULL;


--
-- TOC entry 5958 (class 2606 OID 23447)
-- Name: employee_goals employee_goals_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5959 (class 2606 OID 23472)
-- Name: employee_goals employee_goals_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5960 (class 2606 OID 23452)
-- Name: employee_goals employee_goals_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5961 (class 2606 OID 23467)
-- Name: employee_goals employee_goals_parent_goal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_parent_goal_id_fkey FOREIGN KEY (parent_goal_id) REFERENCES public.employee_goals(id);


--
-- TOC entry 5962 (class 2606 OID 23462)
-- Name: employee_goals employee_goals_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_period_id_fkey FOREIGN KEY (period_id) REFERENCES public.appraisal_periods(id) ON DELETE CASCADE;


--
-- TOC entry 5963 (class 2606 OID 23477)
-- Name: employee_goals employee_goals_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5835 (class 2606 OID 19267)
-- Name: employee_history employee_history_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id);


--
-- TOC entry 5836 (class 2606 OID 19227)
-- Name: employee_history employee_history_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5837 (class 2606 OID 19272)
-- Name: employee_history employee_history_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5838 (class 2606 OID 19232)
-- Name: employee_history employee_history_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5839 (class 2606 OID 19252)
-- Name: employee_history employee_history_new_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_new_department_id_fkey FOREIGN KEY (new_department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- TOC entry 5840 (class 2606 OID 19262)
-- Name: employee_history employee_history_new_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_new_manager_id_fkey FOREIGN KEY (new_manager_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 5841 (class 2606 OID 19257)
-- Name: employee_history employee_history_new_position_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_new_position_id_fkey FOREIGN KEY (new_position_id) REFERENCES public.positions(id) ON DELETE SET NULL;


--
-- TOC entry 5842 (class 2606 OID 19237)
-- Name: employee_history employee_history_previous_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_previous_department_id_fkey FOREIGN KEY (previous_department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- TOC entry 5843 (class 2606 OID 19247)
-- Name: employee_history employee_history_previous_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_previous_manager_id_fkey FOREIGN KEY (previous_manager_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 5844 (class 2606 OID 19242)
-- Name: employee_history employee_history_previous_position_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_previous_position_id_fkey FOREIGN KEY (previous_position_id) REFERENCES public.positions(id) ON DELETE SET NULL;


--
-- TOC entry 5845 (class 2606 OID 23902)
-- Name: employee_history employee_history_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_history
    ADD CONSTRAINT employee_history_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6015 (class 2606 OID 29312)
-- Name: employee_job_assignments employee_job_assignments_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_job_assignments
    ADD CONSTRAINT employee_job_assignments_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6016 (class 2606 OID 29322)
-- Name: employee_job_assignments employee_job_assignments_cost_center_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_job_assignments
    ADD CONSTRAINT employee_job_assignments_cost_center_id_fkey FOREIGN KEY (cost_center_id) REFERENCES public.cost_centers(id);


--
-- TOC entry 6017 (class 2606 OID 29317)
-- Name: employee_job_assignments employee_job_assignments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_job_assignments
    ADD CONSTRAINT employee_job_assignments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6018 (class 2606 OID 29327)
-- Name: employee_job_assignments employee_job_assignments_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_job_assignments
    ADD CONSTRAINT employee_job_assignments_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.employees(id);


--
-- TOC entry 6019 (class 2606 OID 29332)
-- Name: employee_job_assignments employee_job_assignments_work_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_job_assignments
    ADD CONSTRAINT employee_job_assignments_work_location_id_fkey FOREIGN KEY (work_location_id) REFERENCES public.work_locations(id);


--
-- TOC entry 6038 (class 2606 OID 31027)
-- Name: employee_leave_entitlements employee_leave_entitlements_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_leave_entitlements
    ADD CONSTRAINT employee_leave_entitlements_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6039 (class 2606 OID 31032)
-- Name: employee_leave_entitlements employee_leave_entitlements_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_leave_entitlements
    ADD CONSTRAINT employee_leave_entitlements_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6040 (class 2606 OID 31037)
-- Name: employee_leave_entitlements employee_leave_entitlements_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_leave_entitlements
    ADD CONSTRAINT employee_leave_entitlements_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE CASCADE;


--
-- TOC entry 6041 (class 2606 OID 31042)
-- Name: employee_leave_entitlements employee_leave_entitlements_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_leave_entitlements
    ADD CONSTRAINT employee_leave_entitlements_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.leave_policies(id) ON DELETE CASCADE;


--
-- TOC entry 5893 (class 2606 OID 20240)
-- Name: employee_loans employee_loans_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_loans
    ADD CONSTRAINT employee_loans_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id);


--
-- TOC entry 5894 (class 2606 OID 20230)
-- Name: employee_loans employee_loans_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_loans
    ADD CONSTRAINT employee_loans_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5895 (class 2606 OID 20245)
-- Name: employee_loans employee_loans_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_loans
    ADD CONSTRAINT employee_loans_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5896 (class 2606 OID 20235)
-- Name: employee_loans employee_loans_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_loans
    ADD CONSTRAINT employee_loans_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5897 (class 2606 OID 20250)
-- Name: employee_loans employee_loans_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_loans
    ADD CONSTRAINT employee_loans_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5993 (class 2606 OID 24363)
-- Name: employee_shift_assignments employee_shift_assignments_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_shift_assignments
    ADD CONSTRAINT employee_shift_assignments_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5994 (class 2606 OID 24368)
-- Name: employee_shift_assignments employee_shift_assignments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_shift_assignments
    ADD CONSTRAINT employee_shift_assignments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5995 (class 2606 OID 24373)
-- Name: employee_shift_assignments employee_shift_assignments_shift_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_shift_assignments
    ADD CONSTRAINT employee_shift_assignments_shift_template_id_fkey FOREIGN KEY (shift_template_id) REFERENCES public.shift_templates(id) ON DELETE RESTRICT;


--
-- TOC entry 5996 (class 2606 OID 24378)
-- Name: employee_shift_assignments employee_shift_assignments_work_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_shift_assignments
    ADD CONSTRAINT employee_shift_assignments_work_location_id_fkey FOREIGN KEY (work_location_id) REFERENCES public.work_locations(id) ON DELETE SET NULL;


--
-- TOC entry 6066 (class 2606 OID 32222)
-- Name: employee_shifts employee_shifts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_shifts
    ADD CONSTRAINT employee_shifts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6067 (class 2606 OID 32227)
-- Name: employee_shifts employee_shifts_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_shifts
    ADD CONSTRAINT employee_shifts_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6068 (class 2606 OID 32232)
-- Name: employee_shifts employee_shifts_shift_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_shifts
    ADD CONSTRAINT employee_shifts_shift_template_id_fkey FOREIGN KEY (shift_template_id) REFERENCES public.shift_templates(id) ON DELETE SET NULL;


--
-- TOC entry 6023 (class 2606 OID 29465)
-- Name: employee_work_schedules employee_work_schedules_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_work_schedules
    ADD CONSTRAINT employee_work_schedules_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6024 (class 2606 OID 29470)
-- Name: employee_work_schedules employee_work_schedules_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_work_schedules
    ADD CONSTRAINT employee_work_schedules_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5818 (class 2606 OID 24239)
-- Name: employees employees_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5819 (class 2606 OID 18942)
-- Name: employees employees_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5820 (class 2606 OID 18927)
-- Name: employees employees_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- TOC entry 5821 (class 2606 OID 18937)
-- Name: employees employees_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 5822 (class 2606 OID 18932)
-- Name: employees employees_position_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_position_id_fkey FOREIGN KEY (position_id) REFERENCES public.positions(id) ON DELETE SET NULL;


--
-- TOC entry 5823 (class 2606 OID 18947)
-- Name: employees employees_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5887 (class 2606 OID 23942)
-- Name: epf_rates epf_rates_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.epf_rates
    ADD CONSTRAINT epf_rates_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5888 (class 2606 OID 23947)
-- Name: epf_rates epf_rates_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.epf_rates
    ADD CONSTRAINT epf_rates_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5970 (class 2606 OID 36146)
-- Name: appraisal_competency_ratings fk_acr_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_competency_ratings
    ADD CONSTRAINT fk_acr_company FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;


--
-- TOC entry 5973 (class 2606 OID 36151)
-- Name: appraisal_goal_ratings fk_agr_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_goal_ratings
    ADD CONSTRAINT fk_agr_company FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;


--
-- TOC entry 5948 (class 2606 OID 36156)
-- Name: appraisal_template_competencies fk_atc_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appraisal_template_competencies
    ADD CONSTRAINT fk_atc_company FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;


--
-- TOC entry 5902 (class 2606 OID 32553)
-- Name: attendance_records fk_attendance_device; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT fk_attendance_device FOREIGN KEY (device_id) REFERENCES public.device_register(id) ON DELETE SET NULL;


--
-- TOC entry 5903 (class 2606 OID 22818)
-- Name: attendance_records fk_attendance_employee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT fk_attendance_employee FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5904 (class 2606 OID 32548)
-- Name: attendance_records fk_attendance_geo_location; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT fk_attendance_geo_location FOREIGN KEY (geo_location_id) REFERENCES public.geo_locations(id) ON DELETE SET NULL;


--
-- TOC entry 5905 (class 2606 OID 32538)
-- Name: attendance_records fk_attendance_shift_assignment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT fk_attendance_shift_assignment FOREIGN KEY (shift_assignment_id) REFERENCES public.employee_shifts(id) ON DELETE SET NULL;


--
-- TOC entry 5906 (class 2606 OID 32543)
-- Name: attendance_records fk_attendance_shift_template; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_records
    ADD CONSTRAINT fk_attendance_shift_template FOREIGN KEY (shift_template_id) REFERENCES public.shift_templates(id) ON DELETE SET NULL;


--
-- TOC entry 6117 (class 2606 OID 36526)
-- Name: company_links fk_cl_ancestor; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_links
    ADD CONSTRAINT fk_cl_ancestor FOREIGN KEY (ancestor_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6118 (class 2606 OID 36531)
-- Name: company_links fk_cl_descendant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_links
    ADD CONSTRAINT fk_cl_descendant FOREIGN KEY (descendant_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5796 (class 2606 OID 36514)
-- Name: companies fk_companies_parent; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT fk_companies_parent FOREIGN KEY (parent_company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;


--
-- TOC entry 5810 (class 2606 OID 18966)
-- Name: departments fk_departments_manager; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT fk_departments_manager FOREIGN KEY (manager_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 5924 (class 2606 OID 22808)
-- Name: employee_claims fk_employee_claim_type; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_claims
    ADD CONSTRAINT fk_employee_claim_type FOREIGN KEY (claim_type_id) REFERENCES public.claim_types(id) ON DELETE RESTRICT;


--
-- TOC entry 5925 (class 2606 OID 22813)
-- Name: employee_claims fk_employee_claims_payroll_batch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_claims
    ADD CONSTRAINT fk_employee_claims_payroll_batch FOREIGN KEY (paid_in_payroll_batch_id) REFERENCES public.payroll_batches(id) ON DELETE SET NULL;


--
-- TOC entry 6020 (class 2606 OID 30208)
-- Name: employee_job_assignments fk_employee_job_assignments_position; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_job_assignments
    ADD CONSTRAINT fk_employee_job_assignments_position FOREIGN KEY (company_id, position_id) REFERENCES public.positions(company_id, id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 5824 (class 2606 OID 26755)
-- Name: employees fk_employees_cost_center_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT fk_employees_cost_center_tenant FOREIGN KEY (company_id, cost_center_id) REFERENCES public.cost_centers(company_id, id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 5825 (class 2606 OID 26896)
-- Name: employees fk_employees_work_location_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT fk_employees_work_location_tenant FOREIGN KEY (company_id, work_location_id) REFERENCES public.work_locations(company_id, id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 5999 (class 2606 OID 27376)
-- Name: gl_accounts fk_gl_accounts_parent_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_accounts
    ADD CONSTRAINT fk_gl_accounts_parent_tenant FOREIGN KEY (company_id, parent_id) REFERENCES public.gl_accounts(company_id, id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 6093 (class 2606 OID 34120)
-- Name: headcount_plans fk_hc_plan_cost_center; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_plans
    ADD CONSTRAINT fk_hc_plan_cost_center FOREIGN KEY (cost_center_id) REFERENCES public.cost_centers(id) ON DELETE SET NULL;


--
-- TOC entry 6099 (class 2606 OID 34781)
-- Name: headcount_requests fk_hreq_cost_center; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_requests
    ADD CONSTRAINT fk_hreq_cost_center FOREIGN KEY (cost_center_id) REFERENCES public.cost_centers(id) ON DELETE SET NULL;


--
-- TOC entry 6006 (class 2606 OID 27776)
-- Name: gl_journal_lines fk_journal_lines_cost_center; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_journal_lines
    ADD CONSTRAINT fk_journal_lines_cost_center FOREIGN KEY (company_id, cost_center_id) REFERENCES public.cost_centers(company_id, id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 6007 (class 2606 OID 27771)
-- Name: gl_journal_lines fk_journal_lines_credit; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_journal_lines
    ADD CONSTRAINT fk_journal_lines_credit FOREIGN KEY (company_id, credit_gl_account_id) REFERENCES public.gl_accounts(company_id, id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 6008 (class 2606 OID 27766)
-- Name: gl_journal_lines fk_journal_lines_debit; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_journal_lines
    ADD CONSTRAINT fk_journal_lines_debit FOREIGN KEY (company_id, debit_gl_account_id) REFERENCES public.gl_accounts(company_id, id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 6009 (class 2606 OID 27781)
-- Name: gl_journal_lines fk_journal_lines_employee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_journal_lines
    ADD CONSTRAINT fk_journal_lines_employee FOREIGN KEY (company_id, employee_id) REFERENCES public.employees(company_id, id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 6105 (class 2606 OID 34950)
-- Name: job_requisitions fk_jreq_cost_center; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisitions
    ADD CONSTRAINT fk_jreq_cost_center FOREIGN KEY (cost_center_id) REFERENCES public.cost_centers(id) ON DELETE SET NULL;


--
-- TOC entry 5863 (class 2606 OID 36161)
-- Name: leave_approval_history fk_lah_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approval_history
    ADD CONSTRAINT fk_lah_company FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;


--
-- TOC entry 6029 (class 2606 OID 29759)
-- Name: org_units fk_org_units_parent_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_units
    ADD CONSTRAINT fk_org_units_parent_tenant FOREIGN KEY (company_id, parent_id) REFERENCES public.org_units(company_id, id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 5907 (class 2606 OID 35380)
-- Name: overtime_approvals fk_ot_appr_employee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_approvals
    ADD CONSTRAINT fk_ot_appr_employee FOREIGN KEY (approver_employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 5987 (class 2606 OID 32693)
-- Name: overtime_requests fk_ot_payroll_batch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_requests
    ADD CONSTRAINT fk_ot_payroll_batch FOREIGN KEY (payroll_batch_id) REFERENCES public.payroll_batches(id) ON DELETE SET NULL;


--
-- TOC entry 5908 (class 2606 OID 24069)
-- Name: overtime_approvals fk_overtime_approvals_request; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_approvals
    ADD CONSTRAINT fk_overtime_approvals_request FOREIGN KEY (overtime_request_id) REFERENCES public.overtime_requests(id) ON DELETE SET NULL;


--
-- TOC entry 5909 (class 2606 OID 22823)
-- Name: overtime_approvals fk_overtime_employee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_approvals
    ADD CONSTRAINT fk_overtime_employee FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6001 (class 2606 OID 27457)
-- Name: payroll_component_gl_mappings fk_payroll_cost_center; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_component_gl_mappings
    ADD CONSTRAINT fk_payroll_cost_center FOREIGN KEY (company_id, cost_center_id) REFERENCES public.cost_centers(company_id, id) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 6002 (class 2606 OID 27452)
-- Name: payroll_component_gl_mappings fk_payroll_gl_credit; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_component_gl_mappings
    ADD CONSTRAINT fk_payroll_gl_credit FOREIGN KEY (company_id, credit_gl_account_id) REFERENCES public.gl_accounts(company_id, id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 6003 (class 2606 OID 27447)
-- Name: payroll_component_gl_mappings fk_payroll_gl_debit; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_component_gl_mappings
    ADD CONSTRAINT fk_payroll_gl_debit FOREIGN KEY (company_id, debit_gl_account_id) REFERENCES public.gl_accounts(company_id, id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 6089 (class 2606 OID 34034)
-- Name: position_assignments fk_pos_assign_cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.position_assignments
    ADD CONSTRAINT fk_pos_assign_cc FOREIGN KEY (cost_center_id) REFERENCES public.cost_centers(id) ON DELETE SET NULL;


--
-- TOC entry 5811 (class 2606 OID 33224)
-- Name: positions fk_positions_cost_center; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT fk_positions_cost_center FOREIGN KEY (cost_center_id) REFERENCES public.cost_centers(id) ON DELETE SET NULL;


--
-- TOC entry 5812 (class 2606 OID 30019)
-- Name: positions fk_positions_job_catalog; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT fk_positions_job_catalog FOREIGN KEY (job_catalog_id) REFERENCES public.job_catalog(id) ON DELETE CASCADE;


--
-- TOC entry 5813 (class 2606 OID 30014)
-- Name: positions fk_positions_org_unit; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT fk_positions_org_unit FOREIGN KEY (org_unit_id) REFERENCES public.org_units(id) ON DELETE CASCADE;


--
-- TOC entry 5800 (class 2606 OID 36166)
-- Name: user_sessions fk_sessions_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT fk_sessions_company FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;


--
-- TOC entry 5991 (class 2606 OID 32145)
-- Name: shift_templates fk_shift_templates_work_schedule; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_templates
    ADD CONSTRAINT fk_shift_templates_work_schedule FOREIGN KEY (work_schedule_id) REFERENCES public.work_schedules(id) ON DELETE SET NULL;


--
-- TOC entry 5797 (class 2606 OID 18961)
-- Name: users fk_users_employee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_users_employee FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 6069 (class 2606 OID 32305)
-- Name: geo_locations geo_locations_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geo_locations
    ADD CONSTRAINT geo_locations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6000 (class 2606 OID 27370)
-- Name: gl_accounts gl_accounts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_accounts
    ADD CONSTRAINT gl_accounts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6005 (class 2606 OID 27521)
-- Name: gl_journal_headers gl_journal_headers_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_journal_headers
    ADD CONSTRAINT gl_journal_headers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6010 (class 2606 OID 27755)
-- Name: gl_journal_lines gl_journal_lines_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_journal_lines
    ADD CONSTRAINT gl_journal_lines_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6011 (class 2606 OID 27760)
-- Name: gl_journal_lines gl_journal_lines_journal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gl_journal_lines
    ADD CONSTRAINT gl_journal_lines_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES public.gl_journal_headers(id) ON DELETE CASCADE;


--
-- TOC entry 5964 (class 2606 OID 23500)
-- Name: goal_milestones goal_milestones_goal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goal_milestones
    ADD CONSTRAINT goal_milestones_goal_id_fkey FOREIGN KEY (goal_id) REFERENCES public.employee_goals(id) ON DELETE CASCADE;


--
-- TOC entry 6104 (class 2606 OID 34851)
-- Name: headcount_approvals headcount_approvals_headcount_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_approvals
    ADD CONSTRAINT headcount_approvals_headcount_request_id_fkey FOREIGN KEY (headcount_request_id) REFERENCES public.headcount_requests(id) ON DELETE CASCADE;


--
-- TOC entry 6094 (class 2606 OID 34111)
-- Name: headcount_plans headcount_plans_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_plans
    ADD CONSTRAINT headcount_plans_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6100 (class 2606 OID 34761)
-- Name: headcount_requests headcount_requests_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_requests
    ADD CONSTRAINT headcount_requests_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6101 (class 2606 OID 34776)
-- Name: headcount_requests headcount_requests_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_requests
    ADD CONSTRAINT headcount_requests_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.approval_policies(id) ON DELETE SET NULL;


--
-- TOC entry 6102 (class 2606 OID 34771)
-- Name: headcount_requests headcount_requests_position_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_requests
    ADD CONSTRAINT headcount_requests_position_id_fkey FOREIGN KEY (position_id) REFERENCES public.positions(id) ON DELETE SET NULL;


--
-- TOC entry 6103 (class 2606 OID 34766)
-- Name: headcount_requests headcount_requests_requester_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.headcount_requests
    ADD CONSTRAINT headcount_requests_requester_employee_id_fkey FOREIGN KEY (requester_employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 6057 (class 2606 OID 31590)
-- Name: holiday_calendar holiday_calendar_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.holiday_calendar
    ADD CONSTRAINT holiday_calendar_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6031 (class 2606 OID 29820)
-- Name: job_catalog job_catalog_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_catalog
    ADD CONSTRAINT job_catalog_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6112 (class 2606 OID 35021)
-- Name: job_requisition_approvals job_requisition_approvals_job_requisition_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisition_approvals
    ADD CONSTRAINT job_requisition_approvals_job_requisition_id_fkey FOREIGN KEY (job_requisition_id) REFERENCES public.job_requisitions(id) ON DELETE CASCADE;


--
-- TOC entry 6106 (class 2606 OID 34920)
-- Name: job_requisitions job_requisitions_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisitions
    ADD CONSTRAINT job_requisitions_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6107 (class 2606 OID 34945)
-- Name: job_requisitions job_requisitions_headcount_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisitions
    ADD CONSTRAINT job_requisitions_headcount_request_id_fkey FOREIGN KEY (headcount_request_id) REFERENCES public.headcount_requests(id) ON DELETE SET NULL;


--
-- TOC entry 6108 (class 2606 OID 34930)
-- Name: job_requisitions job_requisitions_hiring_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisitions
    ADD CONSTRAINT job_requisitions_hiring_manager_id_fkey FOREIGN KEY (hiring_manager_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 6109 (class 2606 OID 34940)
-- Name: job_requisitions job_requisitions_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisitions
    ADD CONSTRAINT job_requisitions_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.approval_policies(id) ON DELETE SET NULL;


--
-- TOC entry 6110 (class 2606 OID 34935)
-- Name: job_requisitions job_requisitions_position_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisitions
    ADD CONSTRAINT job_requisitions_position_id_fkey FOREIGN KEY (position_id) REFERENCES public.positions(id) ON DELETE SET NULL;


--
-- TOC entry 6111 (class 2606 OID 34925)
-- Name: job_requisitions job_requisitions_requester_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisitions
    ADD CONSTRAINT job_requisitions_requester_employee_id_fkey FOREIGN KEY (requester_employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 6079 (class 2606 OID 32860)
-- Name: kiosk_sessions kiosk_sessions_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kiosk_sessions
    ADD CONSTRAINT kiosk_sessions_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6080 (class 2606 OID 32865)
-- Name: kiosk_sessions kiosk_sessions_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kiosk_sessions
    ADD CONSTRAINT kiosk_sessions_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.device_register(id) ON DELETE SET NULL;


--
-- TOC entry 6081 (class 2606 OID 32870)
-- Name: kiosk_sessions kiosk_sessions_geo_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kiosk_sessions
    ADD CONSTRAINT kiosk_sessions_geo_location_id_fkey FOREIGN KEY (geo_location_id) REFERENCES public.geo_locations(id) ON DELETE SET NULL;


--
-- TOC entry 6061 (class 2606 OID 31795)
-- Name: leave_accrual_log leave_accrual_log_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_accrual_log
    ADD CONSTRAINT leave_accrual_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6062 (class 2606 OID 31805)
-- Name: leave_accrual_log leave_accrual_log_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_accrual_log
    ADD CONSTRAINT leave_accrual_log_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6063 (class 2606 OID 31810)
-- Name: leave_accrual_log leave_accrual_log_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_accrual_log
    ADD CONSTRAINT leave_accrual_log_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE CASCADE;


--
-- TOC entry 6064 (class 2606 OID 31800)
-- Name: leave_accrual_log leave_accrual_log_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_accrual_log
    ADD CONSTRAINT leave_accrual_log_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.leave_accrual_runs(id) ON DELETE CASCADE;


--
-- TOC entry 6060 (class 2606 OID 31735)
-- Name: leave_accrual_runs leave_accrual_runs_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_accrual_runs
    ADD CONSTRAINT leave_accrual_runs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5854 (class 2606 OID 19717)
-- Name: leave_applications leave_applications_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES public.users(id);


--
-- TOC entry 5855 (class 2606 OID 19722)
-- Name: leave_applications leave_applications_cancelled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_cancelled_by_fkey FOREIGN KEY (cancelled_by) REFERENCES public.users(id);


--
-- TOC entry 5856 (class 2606 OID 19692)
-- Name: leave_applications leave_applications_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5857 (class 2606 OID 19712)
-- Name: leave_applications leave_applications_covering_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_covering_employee_id_fkey FOREIGN KEY (covering_employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- TOC entry 5858 (class 2606 OID 19727)
-- Name: leave_applications leave_applications_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5859 (class 2606 OID 19697)
-- Name: leave_applications leave_applications_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5860 (class 2606 OID 19707)
-- Name: leave_applications leave_applications_leave_entitlement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_leave_entitlement_id_fkey FOREIGN KEY (leave_entitlement_id) REFERENCES public.leave_entitlements(id);


--
-- TOC entry 5861 (class 2606 OID 19702)
-- Name: leave_applications leave_applications_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE CASCADE;


--
-- TOC entry 5862 (class 2606 OID 19732)
-- Name: leave_applications leave_applications_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_applications
    ADD CONSTRAINT leave_applications_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5864 (class 2606 OID 19753)
-- Name: leave_approval_history leave_approval_history_leave_application_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approval_history
    ADD CONSTRAINT leave_approval_history_leave_application_id_fkey FOREIGN KEY (leave_application_id) REFERENCES public.leave_applications(id) ON DELETE CASCADE;


--
-- TOC entry 5865 (class 2606 OID 19758)
-- Name: leave_approval_history leave_approval_history_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approval_history
    ADD CONSTRAINT leave_approval_history_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id);


--
-- TOC entry 6052 (class 2606 OID 31354)
-- Name: leave_approvals leave_approvals_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approvals
    ADD CONSTRAINT leave_approvals_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES public.employees(id) ON DELETE RESTRICT;


--
-- TOC entry 6053 (class 2606 OID 31344)
-- Name: leave_approvals leave_approvals_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approvals
    ADD CONSTRAINT leave_approvals_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6054 (class 2606 OID 31349)
-- Name: leave_approvals leave_approvals_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_approvals
    ADD CONSTRAINT leave_approvals_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.leave_requests(id) ON DELETE CASCADE;


--
-- TOC entry 5869 (class 2606 OID 19800)
-- Name: leave_balance_adjustments leave_balance_adjustments_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balance_adjustments
    ADD CONSTRAINT leave_balance_adjustments_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5870 (class 2606 OID 19815)
-- Name: leave_balance_adjustments leave_balance_adjustments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balance_adjustments
    ADD CONSTRAINT leave_balance_adjustments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5871 (class 2606 OID 19805)
-- Name: leave_balance_adjustments leave_balance_adjustments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balance_adjustments
    ADD CONSTRAINT leave_balance_adjustments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5872 (class 2606 OID 19810)
-- Name: leave_balance_adjustments leave_balance_adjustments_leave_entitlement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balance_adjustments
    ADD CONSTRAINT leave_balance_adjustments_leave_entitlement_id_fkey FOREIGN KEY (leave_entitlement_id) REFERENCES public.leave_entitlements(id) ON DELETE CASCADE;


--
-- TOC entry 5873 (class 2606 OID 23887)
-- Name: leave_balance_adjustments leave_balance_adjustments_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balance_adjustments
    ADD CONSTRAINT leave_balance_adjustments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6042 (class 2606 OID 31105)
-- Name: leave_balances leave_balances_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6043 (class 2606 OID 31110)
-- Name: leave_balances leave_balances_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6044 (class 2606 OID 31115)
-- Name: leave_balances leave_balances_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE CASCADE;


--
-- TOC entry 5866 (class 2606 OID 19778)
-- Name: leave_blackout_periods leave_blackout_periods_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_blackout_periods
    ADD CONSTRAINT leave_blackout_periods_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5867 (class 2606 OID 19783)
-- Name: leave_blackout_periods leave_blackout_periods_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_blackout_periods
    ADD CONSTRAINT leave_blackout_periods_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5868 (class 2606 OID 23882)
-- Name: leave_blackout_periods leave_blackout_periods_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_blackout_periods
    ADD CONSTRAINT leave_blackout_periods_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6055 (class 2606 OID 31412)
-- Name: leave_cancel_history leave_cancel_history_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_cancel_history
    ADD CONSTRAINT leave_cancel_history_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6056 (class 2606 OID 31417)
-- Name: leave_cancel_history leave_cancel_history_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_cancel_history
    ADD CONSTRAINT leave_cancel_history_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.leave_requests(id) ON DELETE CASCADE;


--
-- TOC entry 5849 (class 2606 OID 19615)
-- Name: leave_entitlements leave_entitlements_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_entitlements
    ADD CONSTRAINT leave_entitlements_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5850 (class 2606 OID 23872)
-- Name: leave_entitlements leave_entitlements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_entitlements
    ADD CONSTRAINT leave_entitlements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5851 (class 2606 OID 19620)
-- Name: leave_entitlements leave_entitlements_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_entitlements
    ADD CONSTRAINT leave_entitlements_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5852 (class 2606 OID 19625)
-- Name: leave_entitlements leave_entitlements_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_entitlements
    ADD CONSTRAINT leave_entitlements_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE CASCADE;


--
-- TOC entry 5853 (class 2606 OID 23877)
-- Name: leave_entitlements leave_entitlements_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_entitlements
    ADD CONSTRAINT leave_entitlements_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6045 (class 2606 OID 31174)
-- Name: leave_ledger leave_ledger_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_ledger
    ADD CONSTRAINT leave_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6046 (class 2606 OID 31179)
-- Name: leave_ledger leave_ledger_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_ledger
    ADD CONSTRAINT leave_ledger_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6047 (class 2606 OID 31184)
-- Name: leave_ledger leave_ledger_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_ledger
    ADD CONSTRAINT leave_ledger_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE CASCADE;


--
-- TOC entry 6033 (class 2606 OID 30872)
-- Name: leave_policies leave_policies_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_policies
    ADD CONSTRAINT leave_policies_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6034 (class 2606 OID 30877)
-- Name: leave_policies leave_policies_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_policies
    ADD CONSTRAINT leave_policies_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE CASCADE;


--
-- TOC entry 6035 (class 2606 OID 30935)
-- Name: leave_policy_group_map leave_policy_group_map_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_policy_group_map
    ADD CONSTRAINT leave_policy_group_map_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6036 (class 2606 OID 30940)
-- Name: leave_policy_group_map leave_policy_group_map_leave_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_policy_group_map
    ADD CONSTRAINT leave_policy_group_map_leave_policy_id_fkey FOREIGN KEY (leave_policy_id) REFERENCES public.leave_policies(id) ON DELETE CASCADE;


--
-- TOC entry 6037 (class 2606 OID 30945)
-- Name: leave_policy_group_map leave_policy_group_map_policy_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_policy_group_map
    ADD CONSTRAINT leave_policy_group_map_policy_group_id_fkey FOREIGN KEY (policy_group_id) REFERENCES public.leave_policy_groups(id) ON DELETE CASCADE;


--
-- TOC entry 6032 (class 2606 OID 30675)
-- Name: leave_policy_groups leave_policy_groups_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_policy_groups
    ADD CONSTRAINT leave_policy_groups_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6048 (class 2606 OID 31268)
-- Name: leave_requests leave_requests_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6049 (class 2606 OID 31273)
-- Name: leave_requests leave_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6050 (class 2606 OID 31278)
-- Name: leave_requests leave_requests_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE CASCADE;


--
-- TOC entry 6051 (class 2606 OID 31283)
-- Name: leave_requests leave_requests_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.leave_policies(id) ON DELETE SET NULL;


--
-- TOC entry 5846 (class 2606 OID 19539)
-- Name: leave_types leave_types_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT leave_types_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5847 (class 2606 OID 19544)
-- Name: leave_types leave_types_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT leave_types_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5848 (class 2606 OID 19549)
-- Name: leave_types leave_types_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT leave_types_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5926 (class 2606 OID 22351)
-- Name: notification_queue notification_queue_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_queue
    ADD CONSTRAINT notification_queue_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5927 (class 2606 OID 23932)
-- Name: notification_queue notification_queue_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_queue
    ADD CONSTRAINT notification_queue_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5928 (class 2606 OID 23937)
-- Name: notification_queue notification_queue_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_queue
    ADD CONSTRAINT notification_queue_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6030 (class 2606 OID 29753)
-- Name: org_units org_units_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.org_units
    ADD CONSTRAINT org_units_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5910 (class 2606 OID 22116)
-- Name: overtime_approvals overtime_approvals_approver_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_approvals
    ADD CONSTRAINT overtime_approvals_approver_fk FOREIGN KEY (approver_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5911 (class 2606 OID 22106)
-- Name: overtime_approvals overtime_approvals_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_approvals
    ADD CONSTRAINT overtime_approvals_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5912 (class 2606 OID 22121)
-- Name: overtime_approvals overtime_approvals_created_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_approvals
    ADD CONSTRAINT overtime_approvals_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5913 (class 2606 OID 22111)
-- Name: overtime_approvals overtime_approvals_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_approvals
    ADD CONSTRAINT overtime_approvals_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5914 (class 2606 OID 22126)
-- Name: overtime_approvals overtime_approvals_updated_by_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_approvals
    ADD CONSTRAINT overtime_approvals_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5988 (class 2606 OID 24244)
-- Name: overtime_requests overtime_requests_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_requests
    ADD CONSTRAINT overtime_requests_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5989 (class 2606 OID 24060)
-- Name: overtime_requests overtime_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.overtime_requests
    ADD CONSTRAINT overtime_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5877 (class 2606 OID 20007)
-- Name: payroll_batches payroll_batches_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_batches
    ADD CONSTRAINT payroll_batches_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id);


--
-- TOC entry 5878 (class 2606 OID 20002)
-- Name: payroll_batches payroll_batches_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_batches
    ADD CONSTRAINT payroll_batches_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5879 (class 2606 OID 20017)
-- Name: payroll_batches payroll_batches_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_batches
    ADD CONSTRAINT payroll_batches_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5880 (class 2606 OID 20012)
-- Name: payroll_batches payroll_batches_locked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_batches
    ADD CONSTRAINT payroll_batches_locked_by_fkey FOREIGN KEY (locked_by) REFERENCES public.users(id);


--
-- TOC entry 5881 (class 2606 OID 20022)
-- Name: payroll_batches payroll_batches_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_batches
    ADD CONSTRAINT payroll_batches_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6004 (class 2606 OID 27440)
-- Name: payroll_component_gl_mappings payroll_component_gl_mappings_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_component_gl_mappings
    ADD CONSTRAINT payroll_component_gl_mappings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5882 (class 2606 OID 20121)
-- Name: payroll_items payroll_items_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_items
    ADD CONSTRAINT payroll_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5883 (class 2606 OID 23907)
-- Name: payroll_items payroll_items_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_items
    ADD CONSTRAINT payroll_items_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5884 (class 2606 OID 20126)
-- Name: payroll_items payroll_items_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_items
    ADD CONSTRAINT payroll_items_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 5885 (class 2606 OID 20116)
-- Name: payroll_items payroll_items_payroll_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_items
    ADD CONSTRAINT payroll_items_payroll_batch_id_fkey FOREIGN KEY (payroll_batch_id) REFERENCES public.payroll_batches(id) ON DELETE CASCADE;


--
-- TOC entry 5886 (class 2606 OID 23912)
-- Name: payroll_items payroll_items_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_items
    ADD CONSTRAINT payroll_items_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5891 (class 2606 OID 23962)
-- Name: pcb_tax_schedules pcb_tax_schedules_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcb_tax_schedules
    ADD CONSTRAINT pcb_tax_schedules_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5892 (class 2606 OID 23967)
-- Name: pcb_tax_schedules pcb_tax_schedules_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pcb_tax_schedules
    ADD CONSTRAINT pcb_tax_schedules_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 6090 (class 2606 OID 34019)
-- Name: position_assignments position_assignments_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.position_assignments
    ADD CONSTRAINT position_assignments_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6091 (class 2606 OID 34029)
-- Name: position_assignments position_assignments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.position_assignments
    ADD CONSTRAINT position_assignments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 6092 (class 2606 OID 34024)
-- Name: position_assignments position_assignments_position_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.position_assignments
    ADD CONSTRAINT position_assignments_position_id_fkey FOREIGN KEY (position_id) REFERENCES public.positions(id) ON DELETE CASCADE;


--
-- TOC entry 5814 (class 2606 OID 24234)
-- Name: positions positions_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5815 (class 2606 OID 18841)
-- Name: positions positions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5816 (class 2606 OID 18836)
-- Name: positions positions_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- TOC entry 5817 (class 2606 OID 18846)
-- Name: positions positions_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5874 (class 2606 OID 19921)
-- Name: public_holidays public_holidays_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_holidays
    ADD CONSTRAINT public_holidays_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5875 (class 2606 OID 19926)
-- Name: public_holidays public_holidays_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_holidays
    ADD CONSTRAINT public_holidays_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5876 (class 2606 OID 23917)
-- Name: public_holidays public_holidays_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_holidays
    ADD CONSTRAINT public_holidays_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5938 (class 2606 OID 23258)
-- Name: rating_scale_values rating_scale_values_rating_scale_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rating_scale_values
    ADD CONSTRAINT rating_scale_values_rating_scale_id_fkey FOREIGN KEY (rating_scale_id) REFERENCES public.rating_scales(id) ON DELETE CASCADE;


--
-- TOC entry 5935 (class 2606 OID 23227)
-- Name: rating_scales rating_scales_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rating_scales
    ADD CONSTRAINT rating_scales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5936 (class 2606 OID 23232)
-- Name: rating_scales rating_scales_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rating_scales
    ADD CONSTRAINT rating_scales_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5937 (class 2606 OID 23237)
-- Name: rating_scales rating_scales_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rating_scales
    ADD CONSTRAINT rating_scales_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5992 (class 2606 OID 24345)
-- Name: shift_templates shift_templates_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_templates
    ADD CONSTRAINT shift_templates_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5889 (class 2606 OID 23952)
-- Name: socso_contribution_rates socso_contribution_rates_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.socso_contribution_rates
    ADD CONSTRAINT socso_contribution_rates_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5890 (class 2606 OID 23957)
-- Name: socso_contribution_rates socso_contribution_rates_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.socso_contribution_rates
    ADD CONSTRAINT socso_contribution_rates_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- TOC entry 5801 (class 2606 OID 17567)
-- Name: user_sessions user_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5798 (class 2606 OID 17540)
-- Name: users users_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5799 (class 2606 OID 17545)
-- Name: users users_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 6058 (class 2606 OID 31648)
-- Name: work_calendar_exceptions work_calendar_exceptions_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_calendar_exceptions
    ADD CONSTRAINT work_calendar_exceptions_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6059 (class 2606 OID 31653)
-- Name: work_calendar_exceptions work_calendar_exceptions_org_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_calendar_exceptions
    ADD CONSTRAINT work_calendar_exceptions_org_unit_id_fkey FOREIGN KEY (org_unit_id) REFERENCES public.org_units(id) ON DELETE SET NULL;


--
-- TOC entry 5990 (class 2606 OID 24324)
-- Name: work_locations work_locations_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_locations
    ADD CONSTRAINT work_locations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 6065 (class 2606 OID 31965)
-- Name: work_schedules work_schedules_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5788 (class 2606 OID 16572)
-- Name: objects objects_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- TOC entry 5792 (class 2606 OID 17380)
-- Name: prefixes prefixes_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.prefixes
    ADD CONSTRAINT "prefixes_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- TOC entry 5789 (class 2606 OID 17314)
-- Name: s3_multipart_uploads s3_multipart_uploads_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- TOC entry 5790 (class 2606 OID 17334)
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- TOC entry 5791 (class 2606 OID 17329)
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_upload_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES storage.s3_multipart_uploads(id) ON DELETE CASCADE;


--
-- TOC entry 6659 (class 3256 OID 34666)
-- Name: approval_policy_assignments ap_assign_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_assign_delete ON public.approval_policy_assignments FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6657 (class 3256 OID 34664)
-- Name: approval_policy_assignments ap_assign_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_assign_insert ON public.approval_policy_assignments FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6656 (class 3256 OID 34663)
-- Name: approval_policy_assignments ap_assign_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_assign_select ON public.approval_policy_assignments FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6658 (class 3256 OID 34665)
-- Name: approval_policy_assignments ap_assign_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_assign_update ON public.approval_policy_assignments FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6655 (class 3256 OID 34635)
-- Name: approval_policy_levels ap_levels_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_levels_delete ON public.approval_policy_levels FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6653 (class 3256 OID 34633)
-- Name: approval_policy_levels ap_levels_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_levels_insert ON public.approval_policy_levels FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6652 (class 3256 OID 34632)
-- Name: approval_policy_levels ap_levels_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_levels_select ON public.approval_policy_levels FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6654 (class 3256 OID 34634)
-- Name: approval_policy_levels ap_levels_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_levels_update ON public.approval_policy_levels FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6651 (class 3256 OID 34606)
-- Name: approval_policies ap_policies_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_policies_delete ON public.approval_policies FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6649 (class 3256 OID 34604)
-- Name: approval_policies ap_policies_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_policies_insert ON public.approval_policies FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6648 (class 3256 OID 34603)
-- Name: approval_policies ap_policies_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_policies_select ON public.approval_policies FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6650 (class 3256 OID 34605)
-- Name: approval_policies ap_policies_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ap_policies_update ON public.approval_policies FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6492 (class 0 OID 23587)
-- Dependencies: 433
-- Name: appraisal_approvals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisal_approvals ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6494 (class 0 OID 23642)
-- Dependencies: 435
-- Name: appraisal_comments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisal_comments ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6490 (class 0 OID 23538)
-- Dependencies: 431
-- Name: appraisal_competency_ratings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisal_competency_ratings ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6493 (class 0 OID 23616)
-- Dependencies: 434
-- Name: appraisal_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisal_documents ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6491 (class 0 OID 23562)
-- Dependencies: 432
-- Name: appraisal_goal_ratings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisal_goal_ratings ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6495 (class 0 OID 23676)
-- Dependencies: 436
-- Name: appraisal_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisal_history ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6479 (class 0 OID 23181)
-- Dependencies: 420
-- Name: appraisal_periods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisal_periods ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6489 (class 0 OID 23506)
-- Dependencies: 430
-- Name: appraisal_reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisal_reviews ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6485 (class 0 OID 23349)
-- Dependencies: 426
-- Name: appraisal_template_competencies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisal_template_competencies ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6482 (class 0 OID 23264)
-- Dependencies: 423
-- Name: appraisal_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisal_templates ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6486 (class 0 OID 23373)
-- Dependencies: 427
-- Name: appraisals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appraisals ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6537 (class 0 OID 34582)
-- Dependencies: 495
-- Name: approval_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.approval_policies ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6539 (class 0 OID 34636)
-- Dependencies: 497
-- Name: approval_policy_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.approval_policy_assignments ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6538 (class 0 OID 34607)
-- Dependencies: 496
-- Name: approval_policy_levels; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.approval_policy_levels ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6530 (class 0 OID 32612)
-- Dependencies: 482
-- Name: attendance_exceptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_exceptions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6531 (class 0 OID 32778)
-- Dependencies: 483
-- Name: attendance_qr_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_qr_tokens ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6473 (class 0 OID 22058)
-- Dependencies: 412
-- Name: attendance_records; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6529 (class 0 OID 32426)
-- Dependencies: 481
-- Name: attendance_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_rules ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6533 (class 0 OID 33012)
-- Dependencies: 487
-- Name: attendance_scan_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_scan_logs ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6456 (class 0 OID 17575)
-- Dependencies: 392
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6577 (class 3256 OID 23067)
-- Name: audit_logs audit_logs_select_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_logs_select_same_company ON public.audit_logs FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6475 (class 0 OID 22176)
-- Dependencies: 414
-- Name: claim_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.claim_types ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6551 (class 3256 OID 22468)
-- Name: claim_types claim_types_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY claim_types_all ON public.claim_types USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6453 (class 0 OID 17490)
-- Dependencies: 389
-- Name: companies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6478 (class 0 OID 22358)
-- Dependencies: 417
-- Name: company_notification_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_notification_settings ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6554 (class 3256 OID 22471)
-- Name: company_notification_settings company_notification_settings_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY company_notification_settings_all ON public.company_notification_settings USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6544 (class 3256 OID 20456)
-- Name: companies company_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY company_select_own ON public.companies FOR SELECT USING ((id = public.auth_company_id()));


--
-- TOC entry 6484 (class 0 OID 23323)
-- Dependencies: 425
-- Name: competencies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.competencies ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6483 (class 0 OID 23303)
-- Dependencies: 424
-- Name: competency_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.competency_categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6500 (class 0 OID 26708)
-- Dependencies: 442
-- Name: cost_centers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cost_centers ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6549 (class 3256 OID 26733)
-- Name: cost_centers cost_centers_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cost_centers_delete ON public.cost_centers FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6596 (class 3256 OID 26731)
-- Name: cost_centers cost_centers_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cost_centers_insert ON public.cost_centers FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6595 (class 3256 OID 26730)
-- Name: cost_centers cost_centers_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cost_centers_select ON public.cost_centers FOR SELECT USING (((company_id = public.auth_company_id()) AND (deleted_at IS NULL)));


--
-- TOC entry 6597 (class 3256 OID 26732)
-- Name: cost_centers cost_centers_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cost_centers_update ON public.cost_centers FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6711 (class 3256 OID 36883)
-- Name: attendance_exceptions del_tenant_attendance_exceptions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_attendance_exceptions ON public.attendance_exceptions FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6715 (class 3256 OID 36887)
-- Name: attendance_qr_tokens del_tenant_attendance_qr_tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_attendance_qr_tokens ON public.attendance_qr_tokens FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6699 (class 3256 OID 36871)
-- Name: attendance_records del_tenant_attendance_records; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_attendance_records ON public.attendance_records FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6707 (class 3256 OID 36879)
-- Name: attendance_rules del_tenant_attendance_rules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_attendance_rules ON public.attendance_rules FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6703 (class 3256 OID 36875)
-- Name: attendance_scan_logs del_tenant_attendance_scan_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_attendance_scan_logs ON public.attendance_scan_logs FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6723 (class 3256 OID 36895)
-- Name: employee_shift_assignments del_tenant_employee_shift_assignments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_employee_shift_assignments ON public.employee_shift_assignments FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6719 (class 3256 OID 36891)
-- Name: employee_shifts del_tenant_employee_shifts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_employee_shifts ON public.employee_shifts FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6727 (class 3256 OID 36899)
-- Name: employee_work_schedules del_tenant_employee_work_schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_employee_work_schedules ON public.employee_work_schedules FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6739 (class 3256 OID 36911)
-- Name: leave_entitlements del_tenant_leave_entitlements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_leave_entitlements ON public.leave_entitlements FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6731 (class 3256 OID 36903)
-- Name: overtime_requests del_tenant_overtime_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_overtime_requests ON public.overtime_requests FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6735 (class 3256 OID 36907)
-- Name: payroll_items del_tenant_payroll_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY del_tenant_payroll_items ON public.payroll_items FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6457 (class 0 OID 18740)
-- Dependencies: 393
-- Name: departments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6548 (class 3256 OID 20589)
-- Name: departments departments_delete_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY departments_delete_same_company ON public.departments FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6546 (class 3256 OID 20587)
-- Name: departments departments_insert_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY departments_insert_same_company ON public.departments FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6545 (class 3256 OID 20586)
-- Name: departments departments_select_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY departments_select_same_company ON public.departments FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6547 (class 3256 OID 20588)
-- Name: departments departments_update_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY departments_update_same_company ON public.departments FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6528 (class 0 OID 32356)
-- Dependencies: 480
-- Name: device_register; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.device_register ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6631 (class 3256 OID 32385)
-- Name: device_register device_register_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY device_register_tenant_isolation ON public.device_register USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6505 (class 0 OID 29238)
-- Dependencies: 450
-- Name: employee_actions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_actions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6606 (class 3256 OID 29260)
-- Name: employee_actions employee_actions_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_actions_rw ON public.employee_actions USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6507 (class 0 OID 29382)
-- Dependencies: 452
-- Name: employee_addresses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_addresses ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6608 (class 3256 OID 29406)
-- Name: employee_addresses employee_addresses_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_addresses_rw ON public.employee_addresses USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6460 (class 0 OID 19036)
-- Dependencies: 396
-- Name: employee_allowances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_allowances ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6510 (class 0 OID 29608)
-- Dependencies: 455
-- Name: employee_bank_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_bank_accounts ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6610 (class 3256 OID 29631)
-- Name: employee_bank_accounts employee_bank_accounts_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_bank_accounts_rw ON public.employee_bank_accounts USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6476 (class 0 OID 22207)
-- Dependencies: 415
-- Name: employee_claims; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_claims ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6552 (class 3256 OID 22469)
-- Name: employee_claims employee_claims_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_claims_all ON public.employee_claims USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6509 (class 0 OID 29519)
-- Dependencies: 454
-- Name: employee_compensation; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_compensation ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6609 (class 3256 OID 29547)
-- Name: employee_compensation employee_compensation_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_compensation_rw ON public.employee_compensation USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6461 (class 0 OID 19144)
-- Dependencies: 397
-- Name: employee_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_documents ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6487 (class 0 OID 23432)
-- Dependencies: 428
-- Name: employee_goals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_goals ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6462 (class 0 OID 19218)
-- Dependencies: 398
-- Name: employee_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_history ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6506 (class 0 OID 29302)
-- Dependencies: 451
-- Name: employee_job_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_job_assignments ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6607 (class 3256 OID 29338)
-- Name: employee_job_assignments employee_job_assignments_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_job_assignments_rw ON public.employee_job_assignments USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6516 (class 0 OID 31012)
-- Dependencies: 465
-- Name: employee_leave_entitlements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_leave_entitlements ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6617 (class 3256 OID 31048)
-- Name: employee_leave_entitlements employee_leave_entitlements_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_leave_entitlements_rw ON public.employee_leave_entitlements USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6472 (class 0 OID 20216)
-- Dependencies: 411
-- Name: employee_loans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_loans ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6499 (class 0 OID 24352)
-- Dependencies: 441
-- Name: employee_shift_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_shift_assignments ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6526 (class 0 OID 32210)
-- Dependencies: 478
-- Name: employee_shifts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_shifts ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6508 (class 0 OID 29448)
-- Dependencies: 453
-- Name: employee_work_schedules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_work_schedules ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6459 (class 0 OID 18898)
-- Dependencies: 395
-- Name: employees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6527 (class 0 OID 32290)
-- Dependencies: 479
-- Name: geo_locations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.geo_locations ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6630 (class 3256 OID 32315)
-- Name: geo_locations geo_locations_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY geo_locations_tenant_isolation ON public.geo_locations USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6501 (class 0 OID 27352)
-- Dependencies: 444
-- Name: gl_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gl_accounts ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6599 (class 3256 OID 27386)
-- Name: gl_accounts gl_accounts_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gl_accounts_delete ON public.gl_accounts FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6557 (class 3256 OID 27384)
-- Name: gl_accounts gl_accounts_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gl_accounts_insert ON public.gl_accounts FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6556 (class 3256 OID 27383)
-- Name: gl_accounts gl_accounts_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gl_accounts_select ON public.gl_accounts FOR SELECT USING (((company_id = public.auth_company_id()) AND (deleted_at IS NULL)));


--
-- TOC entry 6598 (class 3256 OID 27385)
-- Name: gl_accounts gl_accounts_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gl_accounts_update ON public.gl_accounts FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6503 (class 0 OID 27508)
-- Dependencies: 446
-- Name: gl_journal_headers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gl_journal_headers ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6604 (class 3256 OID 27786)
-- Name: gl_journal_headers gl_journal_headers_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gl_journal_headers_rw ON public.gl_journal_headers USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6504 (class 0 OID 27746)
-- Dependencies: 447
-- Name: gl_journal_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gl_journal_lines ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6605 (class 3256 OID 27787)
-- Name: gl_journal_lines gl_journal_lines_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gl_journal_lines_rw ON public.gl_journal_lines USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6488 (class 0 OID 23488)
-- Dependencies: 429
-- Name: goal_milestones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.goal_milestones ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6645 (class 3256 OID 34130)
-- Name: headcount_plans hc_plan_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hc_plan_delete ON public.headcount_plans FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6643 (class 3256 OID 34128)
-- Name: headcount_plans hc_plan_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hc_plan_insert ON public.headcount_plans FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6642 (class 3256 OID 34127)
-- Name: headcount_plans hc_plan_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hc_plan_select ON public.headcount_plans FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6644 (class 3256 OID 34129)
-- Name: headcount_plans hc_plan_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hc_plan_update ON public.headcount_plans FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6541 (class 0 OID 34840)
-- Dependencies: 499
-- Name: headcount_approvals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.headcount_approvals ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6535 (class 0 OID 34100)
-- Dependencies: 489
-- Name: headcount_plans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.headcount_plans ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6540 (class 0 OID 34748)
-- Dependencies: 498
-- Name: headcount_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.headcount_requests ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6521 (class 0 OID 31578)
-- Dependencies: 473
-- Name: holiday_calendar; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.holiday_calendar ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6622 (class 3256 OID 31595)
-- Name: holiday_calendar holiday_calendar_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY holiday_calendar_rw ON public.holiday_calendar USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6667 (class 3256 OID 34867)
-- Name: headcount_approvals hreq_appr_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hreq_appr_delete ON public.headcount_approvals FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6665 (class 3256 OID 34865)
-- Name: headcount_approvals hreq_appr_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hreq_appr_insert ON public.headcount_approvals FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6664 (class 3256 OID 34864)
-- Name: headcount_approvals hreq_appr_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hreq_appr_select ON public.headcount_approvals FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6666 (class 3256 OID 34866)
-- Name: headcount_approvals hreq_appr_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hreq_appr_update ON public.headcount_approvals FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6663 (class 3256 OID 34799)
-- Name: headcount_requests hreq_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hreq_delete ON public.headcount_requests FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6661 (class 3256 OID 34797)
-- Name: headcount_requests hreq_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hreq_insert ON public.headcount_requests FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6660 (class 3256 OID 34796)
-- Name: headcount_requests hreq_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hreq_select ON public.headcount_requests FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6662 (class 3256 OID 34798)
-- Name: headcount_requests hreq_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hreq_update ON public.headcount_requests FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6709 (class 3256 OID 36881)
-- Name: attendance_exceptions ins_tenant_attendance_exceptions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_attendance_exceptions ON public.attendance_exceptions FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6713 (class 3256 OID 36885)
-- Name: attendance_qr_tokens ins_tenant_attendance_qr_tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_attendance_qr_tokens ON public.attendance_qr_tokens FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6697 (class 3256 OID 36869)
-- Name: attendance_records ins_tenant_attendance_records; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_attendance_records ON public.attendance_records FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6705 (class 3256 OID 36877)
-- Name: attendance_rules ins_tenant_attendance_rules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_attendance_rules ON public.attendance_rules FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6701 (class 3256 OID 36873)
-- Name: attendance_scan_logs ins_tenant_attendance_scan_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_attendance_scan_logs ON public.attendance_scan_logs FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6721 (class 3256 OID 36893)
-- Name: employee_shift_assignments ins_tenant_employee_shift_assignments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_employee_shift_assignments ON public.employee_shift_assignments FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6717 (class 3256 OID 36889)
-- Name: employee_shifts ins_tenant_employee_shifts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_employee_shifts ON public.employee_shifts FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6725 (class 3256 OID 36897)
-- Name: employee_work_schedules ins_tenant_employee_work_schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_employee_work_schedules ON public.employee_work_schedules FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6737 (class 3256 OID 36909)
-- Name: leave_entitlements ins_tenant_leave_entitlements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_leave_entitlements ON public.leave_entitlements FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6729 (class 3256 OID 36901)
-- Name: overtime_requests ins_tenant_overtime_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_overtime_requests ON public.overtime_requests FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6733 (class 3256 OID 36905)
-- Name: payroll_items ins_tenant_payroll_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ins_tenant_payroll_items ON public.payroll_items FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6512 (class 0 OID 29808)
-- Dependencies: 457
-- Name: job_catalog; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.job_catalog ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6612 (class 3256 OID 29828)
-- Name: job_catalog job_catalog_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY job_catalog_rw ON public.job_catalog USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6543 (class 0 OID 35010)
-- Dependencies: 501
-- Name: job_requisition_approvals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.job_requisition_approvals ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6542 (class 0 OID 34908)
-- Dependencies: 500
-- Name: job_requisitions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.job_requisitions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6675 (class 3256 OID 35037)
-- Name: job_requisition_approvals jreq_appr_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jreq_appr_delete ON public.job_requisition_approvals FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6673 (class 3256 OID 35035)
-- Name: job_requisition_approvals jreq_appr_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jreq_appr_insert ON public.job_requisition_approvals FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6672 (class 3256 OID 35034)
-- Name: job_requisition_approvals jreq_appr_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jreq_appr_select ON public.job_requisition_approvals FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6674 (class 3256 OID 35036)
-- Name: job_requisition_approvals jreq_appr_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jreq_appr_update ON public.job_requisition_approvals FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6671 (class 3256 OID 34968)
-- Name: job_requisitions jreq_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jreq_delete ON public.job_requisitions FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6669 (class 3256 OID 34966)
-- Name: job_requisitions jreq_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jreq_insert ON public.job_requisitions FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6668 (class 3256 OID 34965)
-- Name: job_requisitions jreq_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jreq_select ON public.job_requisitions FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6670 (class 3256 OID 34967)
-- Name: job_requisitions jreq_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY jreq_update ON public.job_requisitions FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6632 (class 3256 OID 32881)
-- Name: kiosk_sessions kiosk_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kiosk_isolation ON public.kiosk_sessions USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6532 (class 0 OID 32848)
-- Dependencies: 484
-- Name: kiosk_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.kiosk_sessions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6524 (class 0 OID 31782)
-- Dependencies: 476
-- Name: leave_accrual_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_accrual_log ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6625 (class 3256 OID 31857)
-- Name: leave_accrual_log leave_accrual_log_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_accrual_log_rw ON public.leave_accrual_log USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6523 (class 0 OID 31722)
-- Dependencies: 475
-- Name: leave_accrual_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_accrual_runs ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6624 (class 3256 OID 31856)
-- Name: leave_accrual_runs leave_accrual_runs_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_accrual_runs_rw ON public.leave_accrual_runs USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6465 (class 0 OID 19676)
-- Dependencies: 401
-- Name: leave_applications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_applications ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6466 (class 0 OID 19744)
-- Dependencies: 402
-- Name: leave_approval_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_approval_history ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6520 (class 0 OID 31330)
-- Dependencies: 469
-- Name: leave_approvals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_approvals ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6621 (class 3256 OID 31360)
-- Name: leave_approvals leave_approvals_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_approvals_rw ON public.leave_approvals USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6468 (class 0 OID 19791)
-- Dependencies: 404
-- Name: leave_balance_adjustments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_balance_adjustments ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6517 (class 0 OID 31090)
-- Dependencies: 466
-- Name: leave_balances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_balances ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6618 (class 3256 OID 31121)
-- Name: leave_balances leave_balances_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_balances_rw ON public.leave_balances USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6467 (class 0 OID 19765)
-- Dependencies: 403
-- Name: leave_blackout_periods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_blackout_periods ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6464 (class 0 OID 19598)
-- Dependencies: 400
-- Name: leave_entitlements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_entitlements ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6518 (class 0 OID 31162)
-- Dependencies: 467
-- Name: leave_ledger; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_ledger ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6619 (class 3256 OID 31190)
-- Name: leave_ledger leave_ledger_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_ledger_rw ON public.leave_ledger USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6514 (class 0 OID 30848)
-- Dependencies: 463
-- Name: leave_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_policies ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6615 (class 3256 OID 30884)
-- Name: leave_policies leave_policies_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_policies_rw ON public.leave_policies USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6515 (class 0 OID 30926)
-- Dependencies: 464
-- Name: leave_policy_group_map; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_policy_group_map ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6616 (class 3256 OID 30951)
-- Name: leave_policy_group_map leave_policy_group_map_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_policy_group_map_rw ON public.leave_policy_group_map USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6513 (class 0 OID 30662)
-- Dependencies: 462
-- Name: leave_policy_groups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_policy_groups ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6614 (class 3256 OID 30682)
-- Name: leave_policy_groups leave_policy_groups_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_policy_groups_rw ON public.leave_policy_groups USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6519 (class 0 OID 31252)
-- Dependencies: 468
-- Name: leave_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6620 (class 3256 OID 31289)
-- Name: leave_requests leave_requests_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_requests_rw ON public.leave_requests USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6463 (class 0 OID 19514)
-- Dependencies: 399
-- Name: leave_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_types ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6613 (class 3256 OID 30601)
-- Name: leave_types leave_types_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_types_rw ON public.leave_types USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6477 (class 0 OID 22338)
-- Dependencies: 416
-- Name: notification_queue; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6553 (class 3256 OID 22470)
-- Name: notification_queue notification_queue_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_queue_all ON public.notification_queue USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6511 (class 0 OID 29738)
-- Dependencies: 456
-- Name: org_units; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.org_units ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6611 (class 3256 OID 29766)
-- Name: org_units org_units_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY org_units_rw ON public.org_units USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6474 (class 0 OID 22094)
-- Dependencies: 413
-- Name: overtime_approvals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.overtime_approvals ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6550 (class 3256 OID 22467)
-- Name: overtime_approvals overtime_approvals_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY overtime_approvals_all ON public.overtime_approvals USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6496 (class 0 OID 24044)
-- Dependencies: 438
-- Name: overtime_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.overtime_requests ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6470 (class 0 OID 19976)
-- Dependencies: 406
-- Name: payroll_batches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_batches ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6502 (class 0 OID 27428)
-- Dependencies: 445
-- Name: payroll_component_gl_mappings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_component_gl_mappings ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6603 (class 3256 OID 27466)
-- Name: payroll_component_gl_mappings payroll_gl_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_gl_delete ON public.payroll_component_gl_mappings FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6601 (class 3256 OID 27464)
-- Name: payroll_component_gl_mappings payroll_gl_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_gl_insert ON public.payroll_component_gl_mappings FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6600 (class 3256 OID 27463)
-- Name: payroll_component_gl_mappings payroll_gl_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_gl_select ON public.payroll_component_gl_mappings FOR SELECT USING (((company_id = public.auth_company_id()) AND (deleted_at IS NULL)));


--
-- TOC entry 6602 (class 3256 OID 27465)
-- Name: payroll_component_gl_mappings payroll_gl_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_gl_update ON public.payroll_component_gl_mappings FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6471 (class 0 OID 20075)
-- Dependencies: 407
-- Name: payroll_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6589 (class 3256 OID 23733)
-- Name: appraisal_approvals policy_appraisal_approvals_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_appraisal_approvals_same_company ON public.appraisal_approvals USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6591 (class 3256 OID 23735)
-- Name: appraisal_comments policy_appraisal_comments_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_appraisal_comments_same_company ON public.appraisal_comments USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6590 (class 3256 OID 23734)
-- Name: appraisal_documents policy_appraisal_documents_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_appraisal_documents_same_company ON public.appraisal_documents USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6592 (class 3256 OID 23736)
-- Name: appraisal_history policy_appraisal_history_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_appraisal_history_same_company ON public.appraisal_history USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6578 (class 3256 OID 23720)
-- Name: appraisal_periods policy_appraisal_periods_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_appraisal_periods_same_company ON public.appraisal_periods USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6588 (class 3256 OID 23730)
-- Name: appraisal_reviews policy_appraisal_reviews_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_appraisal_reviews_same_company ON public.appraisal_reviews USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6582 (class 3256 OID 23723)
-- Name: appraisal_templates policy_appraisal_templates_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_appraisal_templates_same_company ON public.appraisal_templates USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6585 (class 3256 OID 23727)
-- Name: appraisals policy_appraisals_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_appraisals_same_company ON public.appraisals USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6573 (class 3256 OID 23063)
-- Name: audit_logs policy_audit_logs_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_audit_logs_same_company ON public.audit_logs USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6572 (class 3256 OID 23062)
-- Name: claim_types policy_claim_types_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_claim_types_same_company ON public.claim_types USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6574 (class 3256 OID 23064)
-- Name: company_notification_settings policy_company_notification_settings_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_company_notification_settings_same_company ON public.company_notification_settings USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6584 (class 3256 OID 23725)
-- Name: competencies policy_competencies_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_competencies_same_company ON public.competencies USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6583 (class 3256 OID 23724)
-- Name: competency_categories policy_competency_categories_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_competency_categories_same_company ON public.competency_categories USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6555 (class 3256 OID 23044)
-- Name: departments policy_departments_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_departments_same_company ON public.departments USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6560 (class 3256 OID 23048)
-- Name: employee_allowances policy_employee_allowances_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_employee_allowances_same_company ON public.employee_allowances USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6571 (class 3256 OID 23061)
-- Name: employee_claims policy_employee_claims_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_employee_claims_same_company ON public.employee_claims USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6562 (class 3256 OID 23050)
-- Name: employee_documents policy_employee_documents_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_employee_documents_same_company ON public.employee_documents USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6586 (class 3256 OID 23728)
-- Name: employee_goals policy_employee_goals_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_employee_goals_same_company ON public.employee_goals USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6563 (class 3256 OID 23051)
-- Name: employee_history policy_employee_history_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_employee_history_same_company ON public.employee_history USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6569 (class 3256 OID 23058)
-- Name: employee_loans policy_employee_loans_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_employee_loans_same_company ON public.employee_loans USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6559 (class 3256 OID 23047)
-- Name: employees policy_employees_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_employees_same_company ON public.employees USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6587 (class 3256 OID 23729)
-- Name: goal_milestones policy_goal_milestones_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_goal_milestones_same_company ON public.goal_milestones USING ((EXISTS ( SELECT 1
   FROM public.employee_goals eg
  WHERE ((eg.id = goal_milestones.goal_id) AND (eg.company_id = public.auth_company_id())))));


--
-- TOC entry 6561 (class 3256 OID 23049)
-- Name: leave_applications policy_leave_applications_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_leave_applications_same_company ON public.leave_applications USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6565 (class 3256 OID 23053)
-- Name: leave_balance_adjustments policy_leave_balance_adjustments_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_leave_balance_adjustments_same_company ON public.leave_balance_adjustments USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6564 (class 3256 OID 23052)
-- Name: leave_blackout_periods policy_leave_blackout_periods_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_leave_blackout_periods_same_company ON public.leave_blackout_periods USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6567 (class 3256 OID 23055)
-- Name: leave_types policy_leave_types_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_leave_types_same_company ON public.leave_types USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6575 (class 3256 OID 23065)
-- Name: notification_queue policy_notification_queue_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_notification_queue_same_company ON public.notification_queue USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6576 (class 3256 OID 23066)
-- Name: overtime_approvals policy_overtime_approvals_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_overtime_approvals_same_company ON public.overtime_approvals USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6566 (class 3256 OID 23054)
-- Name: payroll_batches policy_payroll_batches_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_payroll_batches_same_company ON public.payroll_batches USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6558 (class 3256 OID 23045)
-- Name: positions policy_positions_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_positions_same_company ON public.positions USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6568 (class 3256 OID 23056)
-- Name: public_holidays policy_public_holidays_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_public_holidays_same_company ON public.public_holidays USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6581 (class 3256 OID 23722)
-- Name: rating_scale_values policy_rating_scale_values_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_rating_scale_values_same_company ON public.rating_scale_values USING ((EXISTS ( SELECT 1
   FROM public.rating_scales rs
  WHERE ((rs.id = rating_scale_values.rating_scale_id) AND (rs.company_id = public.auth_company_id())))));


--
-- TOC entry 6580 (class 3256 OID 23721)
-- Name: rating_scales policy_rating_scales_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_rating_scales_same_company ON public.rating_scales USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6594 (class 3256 OID 24435)
-- Name: shift_templates policy_shift_templates_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_shift_templates_same_company ON public.shift_templates USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6570 (class 3256 OID 23059)
-- Name: users policy_users_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_users_same_company ON public.users USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6593 (class 3256 OID 24434)
-- Name: work_locations policy_work_locations_same_company; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY policy_work_locations_same_company ON public.work_locations USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6641 (class 3256 OID 34055)
-- Name: position_assignments pos_assign_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pos_assign_delete ON public.position_assignments FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6639 (class 3256 OID 34053)
-- Name: position_assignments pos_assign_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pos_assign_insert ON public.position_assignments FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6637 (class 3256 OID 34051)
-- Name: position_assignments pos_assign_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pos_assign_isolation ON public.position_assignments USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6638 (class 3256 OID 34052)
-- Name: position_assignments pos_assign_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pos_assign_select ON public.position_assignments FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6640 (class 3256 OID 34054)
-- Name: position_assignments pos_assign_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pos_assign_update ON public.position_assignments FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6647 (class 3256 OID 34231)
-- Name: position_history poshist_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY poshist_insert ON public.position_history FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6646 (class 3256 OID 34230)
-- Name: position_history poshist_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY poshist_select ON public.position_history FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6534 (class 0 OID 34006)
-- Dependencies: 488
-- Name: position_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.position_assignments ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6536 (class 0 OID 34218)
-- Dependencies: 491
-- Name: position_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.position_history ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6458 (class 0 OID 18820)
-- Dependencies: 394
-- Name: positions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.positions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6636 (class 3256 OID 33275)
-- Name: positions positions_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY positions_delete ON public.positions FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6634 (class 3256 OID 33273)
-- Name: positions positions_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY positions_insert ON public.positions FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6633 (class 3256 OID 33272)
-- Name: positions positions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY positions_select ON public.positions FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6635 (class 3256 OID 33274)
-- Name: positions positions_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY positions_update ON public.positions FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6469 (class 0 OID 19910)
-- Dependencies: 405
-- Name: public_holidays; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.public_holidays ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6481 (class 0 OID 23244)
-- Dependencies: 422
-- Name: rating_scale_values; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rating_scale_values ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6480 (class 0 OID 23213)
-- Dependencies: 421
-- Name: rating_scales; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rating_scales ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6708 (class 3256 OID 36880)
-- Name: attendance_exceptions sel_tenant_attendance_exceptions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_attendance_exceptions ON public.attendance_exceptions FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6712 (class 3256 OID 36884)
-- Name: attendance_qr_tokens sel_tenant_attendance_qr_tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_attendance_qr_tokens ON public.attendance_qr_tokens FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6696 (class 3256 OID 36868)
-- Name: attendance_records sel_tenant_attendance_records; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_attendance_records ON public.attendance_records FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6704 (class 3256 OID 36876)
-- Name: attendance_rules sel_tenant_attendance_rules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_attendance_rules ON public.attendance_rules FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6700 (class 3256 OID 36872)
-- Name: attendance_scan_logs sel_tenant_attendance_scan_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_attendance_scan_logs ON public.attendance_scan_logs FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6720 (class 3256 OID 36892)
-- Name: employee_shift_assignments sel_tenant_employee_shift_assignments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_employee_shift_assignments ON public.employee_shift_assignments FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6716 (class 3256 OID 36888)
-- Name: employee_shifts sel_tenant_employee_shifts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_employee_shifts ON public.employee_shifts FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6724 (class 3256 OID 36896)
-- Name: employee_work_schedules sel_tenant_employee_work_schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_employee_work_schedules ON public.employee_work_schedules FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6736 (class 3256 OID 36908)
-- Name: leave_entitlements sel_tenant_leave_entitlements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_leave_entitlements ON public.leave_entitlements FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6728 (class 3256 OID 36900)
-- Name: overtime_requests sel_tenant_overtime_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_overtime_requests ON public.overtime_requests FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6732 (class 3256 OID 36904)
-- Name: payroll_items sel_tenant_payroll_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sel_tenant_payroll_items ON public.payroll_items FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6498 (class 0 OID 24331)
-- Dependencies: 440
-- Name: shift_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_templates ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6691 (class 3256 OID 36721)
-- Name: appraisal_competency_ratings tenant_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_delete ON public.appraisal_competency_ratings FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6692 (class 3256 OID 36722)
-- Name: appraisal_goal_ratings tenant_delete2; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_delete2 ON public.appraisal_goal_ratings FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6693 (class 3256 OID 36723)
-- Name: appraisal_template_competencies tenant_delete3; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_delete3 ON public.appraisal_template_competencies FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6694 (class 3256 OID 36724)
-- Name: leave_approval_history tenant_delete4; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_delete4 ON public.leave_approval_history FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6695 (class 3256 OID 36725)
-- Name: user_sessions tenant_delete5; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_delete5 ON public.user_sessions FOR DELETE USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6681 (class 3256 OID 36711)
-- Name: appraisal_competency_ratings tenant_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_insert ON public.appraisal_competency_ratings FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6682 (class 3256 OID 36712)
-- Name: appraisal_goal_ratings tenant_insert2; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_insert2 ON public.appraisal_goal_ratings FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6683 (class 3256 OID 36713)
-- Name: appraisal_template_competencies tenant_insert3; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_insert3 ON public.appraisal_template_competencies FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6684 (class 3256 OID 36714)
-- Name: leave_approval_history tenant_insert4; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_insert4 ON public.leave_approval_history FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6685 (class 3256 OID 36715)
-- Name: user_sessions tenant_insert5; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_insert5 ON public.user_sessions FOR INSERT WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6676 (class 3256 OID 36706)
-- Name: appraisal_competency_ratings tenant_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_select ON public.appraisal_competency_ratings FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6677 (class 3256 OID 36707)
-- Name: appraisal_goal_ratings tenant_select2; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_select2 ON public.appraisal_goal_ratings FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6678 (class 3256 OID 36708)
-- Name: appraisal_template_competencies tenant_select3; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_select3 ON public.appraisal_template_competencies FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6679 (class 3256 OID 36709)
-- Name: leave_approval_history tenant_select4; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_select4 ON public.leave_approval_history FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6680 (class 3256 OID 36710)
-- Name: user_sessions tenant_select5; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_select5 ON public.user_sessions FOR SELECT USING (public.company_is_in_scope(company_id));


--
-- TOC entry 6686 (class 3256 OID 36716)
-- Name: appraisal_competency_ratings tenant_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_update ON public.appraisal_competency_ratings FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6687 (class 3256 OID 36717)
-- Name: appraisal_goal_ratings tenant_update2; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_update2 ON public.appraisal_goal_ratings FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6688 (class 3256 OID 36718)
-- Name: appraisal_template_competencies tenant_update3; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_update3 ON public.appraisal_template_competencies FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6689 (class 3256 OID 36719)
-- Name: leave_approval_history tenant_update4; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_update4 ON public.leave_approval_history FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6690 (class 3256 OID 36720)
-- Name: user_sessions tenant_update5; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_update5 ON public.user_sessions FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6710 (class 3256 OID 36882)
-- Name: attendance_exceptions upd_tenant_attendance_exceptions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_attendance_exceptions ON public.attendance_exceptions FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6714 (class 3256 OID 36886)
-- Name: attendance_qr_tokens upd_tenant_attendance_qr_tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_attendance_qr_tokens ON public.attendance_qr_tokens FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6698 (class 3256 OID 36870)
-- Name: attendance_records upd_tenant_attendance_records; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_attendance_records ON public.attendance_records FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6706 (class 3256 OID 36878)
-- Name: attendance_rules upd_tenant_attendance_rules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_attendance_rules ON public.attendance_rules FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6702 (class 3256 OID 36874)
-- Name: attendance_scan_logs upd_tenant_attendance_scan_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_attendance_scan_logs ON public.attendance_scan_logs FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6722 (class 3256 OID 36894)
-- Name: employee_shift_assignments upd_tenant_employee_shift_assignments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_employee_shift_assignments ON public.employee_shift_assignments FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6718 (class 3256 OID 36890)
-- Name: employee_shifts upd_tenant_employee_shifts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_employee_shifts ON public.employee_shifts FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6726 (class 3256 OID 36898)
-- Name: employee_work_schedules upd_tenant_employee_work_schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_employee_work_schedules ON public.employee_work_schedules FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6738 (class 3256 OID 36910)
-- Name: leave_entitlements upd_tenant_leave_entitlements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_leave_entitlements ON public.leave_entitlements FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6730 (class 3256 OID 36902)
-- Name: overtime_requests upd_tenant_overtime_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_overtime_requests ON public.overtime_requests FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6734 (class 3256 OID 36906)
-- Name: payroll_items upd_tenant_payroll_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY upd_tenant_payroll_items ON public.payroll_items FOR UPDATE USING (public.company_is_in_scope(company_id)) WITH CHECK (public.company_is_in_scope(company_id));


--
-- TOC entry 6455 (class 0 OID 17556)
-- Dependencies: 391
-- Name: user_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6454 (class 0 OID 17521)
-- Dependencies: 390
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6522 (class 0 OID 31636)
-- Dependencies: 474
-- Name: work_calendar_exceptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_calendar_exceptions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6623 (class 3256 OID 31658)
-- Name: work_calendar_exceptions work_calendar_exceptions_rw; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_calendar_exceptions_rw ON public.work_calendar_exceptions USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6497 (class 0 OID 24312)
-- Dependencies: 439
-- Name: work_locations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_locations ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6525 (class 0 OID 31938)
-- Dependencies: 477
-- Name: work_schedules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_schedules ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6579 (class 3256 OID 31979)
-- Name: work_schedules work_schedules_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_schedules_delete ON public.work_schedules FOR DELETE USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6628 (class 3256 OID 31977)
-- Name: work_schedules work_schedules_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_schedules_insert ON public.work_schedules FOR INSERT WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6627 (class 3256 OID 31976)
-- Name: work_schedules work_schedules_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_schedules_select ON public.work_schedules FOR SELECT USING ((company_id = public.auth_company_id()));


--
-- TOC entry 6626 (class 3256 OID 31975)
-- Name: work_schedules work_schedules_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_schedules_tenant_isolation ON public.work_schedules USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6629 (class 3256 OID 31978)
-- Name: work_schedules work_schedules_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_schedules_update ON public.work_schedules FOR UPDATE USING ((company_id = public.auth_company_id())) WITH CHECK ((company_id = public.auth_company_id()));


--
-- TOC entry 6446 (class 0 OID 16546)
-- Dependencies: 357
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6452 (class 0 OID 17420)
-- Dependencies: 387
-- Name: buckets_analytics; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets_analytics ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6448 (class 0 OID 16588)
-- Dependencies: 359
-- Name: migrations; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.migrations ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6447 (class 0 OID 16561)
-- Dependencies: 358
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6451 (class 0 OID 17370)
-- Dependencies: 386
-- Name: prefixes; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.prefixes ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6449 (class 0 OID 17305)
-- Dependencies: 383
-- Name: s3_multipart_uploads; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 6450 (class 0 OID 17319)
-- Dependencies: 384
-- Name: s3_multipart_uploads_parts; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

-- Completed on 2025-11-01 01:35:22 +08

--
-- PostgreSQL database dump complete
--

\unrestrict tlgZYvkH63ICJMwjWNvfmEspHiaEi6ONotMFpvgsstgbbbyK2morUUEWDENd7Q7

