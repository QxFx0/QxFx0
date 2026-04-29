INSERT OR IGNORE INTO lex_templates (language_code, template_id, family, move, style, surface_template) VALUES
  ('ru', 'ground_known', 'CMGround', 'MoveGroundKnown', 'formal', 'Известно про {topic:prepositional}.'),
  ('ru', 'define_frame', 'CMDefine', 'MoveDefineFrame', 'formal', 'Определим рамку: {topic:nominative}.'),
  ('ru', 'reflect_mirror', 'CMReflect', 'MoveReflectMirror', 'formal', 'Рефлексия: {topic:nominative}.'),
  ('ru', 'contact_bridge', 'CMContact', 'MoveContactBridge', 'formal', 'Контакт — {topic:nominative}.'),
  ('ru', 'anchor_stabilize', 'CMAnchor', 'MoveAnchorStabilize', 'formal', 'Упор — {topic:nominative}.'),
  ('ru', 'affirm_presence', 'CMContact', 'MoveAffirmPresence', 'formal', 'Я здесь.'),
  ('ru', 'repair_bridge', 'CMRepair', 'MoveRepairBridge', 'formal', 'Вернём контакт — {topic:nominative}.'),
  ('ru', 'hypothesize_test', 'CMHypothesis', 'MoveHypothesizeTest', 'formal', 'А если {topic:nominative}?'),
  ('ru', 'deepen_probe', 'CMDeepen', 'MoveDeepenProbe', 'formal', 'Глубоко: что за {topic:nominative}?'),
  ('ru', 'ground_basis', 'CMGround', 'MoveGroundBasis', 'formal', 'Обоснование: {topic:nominative}.'),
  ('ru', 'purpose_teleology', 'CMPurpose', 'MovePurposeTeleology', 'formal', 'Цель: {topic:genitive}.'),
  ('ru', 'distinguish_contrast', 'CMDistinguish', 'MoveShowContrast', 'formal', 'Есть отличие в {topic:prepositional}.'),
  ('ru', 'next_step', 'CMNextStep', 'MoveNextStep', 'formal', 'Дальше — {topic:nominative}?');

INSERT OR IGNORE INTO lex_cue_rules (language_code, cue_pattern, target_family, target_force, confidence) VALUES
  ('ru', 'что такое', 'CMDefine', 'IFAsk', 0.95),
  ('ru', 'в чём разница', 'CMDistinguish', 'IFAsk', 0.90),
  ('ru', 'зачем', 'CMPurpose', 'IFAsk', 0.85),
  ('ru', 'а если', 'CMHypothesis', 'IFAsk', 0.85),
  ('ru', 'я чувствую', 'CMContact', 'IFContact', 0.80),
  ('ru', 'ты меня слышишь', 'CMContact', 'IFContact', 0.90),
  ('ru', 'я устал', 'CMRepair', 'IFContact', 0.80),
  ('ru', 'расскажи', 'CMDescribe', 'IFAsk', 0.75),
  ('ru', 'не согласен', 'CMConfront', 'IFConfront', 0.80),
  ('ru', 'может быть', 'CMReflect', 'IFAsk', 0.70);
