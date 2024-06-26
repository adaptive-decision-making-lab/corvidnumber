## ---
##
## Script name: wolff_etal_2023_rcode.R
##
## Purpose of script: Analyze pinyon jay number preference data
##
## Authors: London Wolff (lmwolff3@gmail.com) & Jeffrey R. Stevens (jeffrey.r.stevens@gmail.com)
##
## Date Created: 2022-08-12
##
## Date Finalized: 2024-01-05
##
## License: All materials presented here are released under the Creative Commons Attribution 4.0 International Public License (CC BY 4.0).
##  You are free to:
##   Share — copy and redistribute the material in any medium or format
##   Adapt — remix, transform, and build upon the material for any purpose, even commercially.
##  Under the following terms:
##   Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licencor endorses you or your use.
##   No additional restrictions — You may not apply legal terms or technological measures that legally restrict others from doing anything the license permits.
##
##
## ---

# Load libraries ---------------------------------------------------------------

library(tidyverse)
library(patchwork)
library(lme4)
library(car)
library(BayesFactor)
library(bayestestR)
library(performance)
library(papaja)

library(ggcorrplot)
library(psych)

# Define functions -------------------------------------------------------------

# Analyze an experiment's data
analyze_data <- function(df) {

  # Calculate difference and ratio
  df <- df |>
    mutate(
      difference = large_num - small_num,
      ratio = small_num / large_num
    )

  ## Descriptive statistics ------------------------------

  # Summarize data per subject
  choice_means_subject <- df |>
    group_by(subject) |>
    summarise(n = n(), percent_larger = mean(choose_larger, na.rm = TRUE) * 100, .groups = "drop")

  # Difference
  # Summarize data per subject and difference level
  choice_means_subject_diff <- df |>
    group_by(difference, subject) |>
    summarise(percent_larger = mean(choose_larger, na.rm = TRUE) * 100, .groups = "drop")

  # Summarize data per difference level
  choice_means_diff_means <- choice_means_subject_diff |>
    group_by(difference) |>
    summarise(percent_larger = mean(percent_larger), .groups = "drop")

  # Within subject confidence intervals
  wsci_difference <- wsci(
    data = choice_means_subject_diff,
    id = "subject",
    dv = "percent_larger",
    factors = "difference",
    method = "Morey"
  )
  choice_means_diff_means$upper <- choice_means_diff_means$percent_larger + wsci_difference$percent_larger
  choice_means_diff_means$lower <- choice_means_diff_means$percent_larger - wsci_difference$percent_larger

  # Ratio
  # Summarize data per subject and ratio level
  choice_means_subject_ratio <- df |>
    group_by(ratio, subject) |>
    summarise(percent_larger = mean(choose_larger, na.rm = TRUE) * 100, .groups = "drop")

  # Summarize data per ratio level
  choice_means_ratio_means <- choice_means_subject_ratio |>
    group_by(ratio) |>
    summarise(percent_larger = mean(percent_larger), .groups = "drop")

  # Within subject confidence intervals
  wsci_ratio <- wsci(
    data = choice_means_subject_ratio,
    id = "subject",
    dv = "percent_larger",
    factors = "ratio",
    method = "Morey"
  )
  choice_means_ratio_means$upper <- choice_means_ratio_means$percent_larger + wsci_ratio$percent_larger
  choice_means_ratio_means$lower <- choice_means_ratio_means$percent_larger - wsci_ratio$percent_larger


  ## t-tests ------------------------------
  ttest_normality <- shapiro.test(choice_means_subject$percent_larger)
  large_pref_ttest <- t.test(choice_means_subject$percent_larger, mu = 50, alternative = "two.sided")
  large_pref_ttest_bf <- ttestBF(choice_means_subject$percent_larger, mu = 50, alternative = "two.sided")


  ## Model selection ----------------------------------------------
  # First we find the best-fitting random effect model, plug this random effect structure into the fixed effect models, and then test for best fixed effect structure.

  ## Random effects structure selection ------------------

  random_effect_intercept <- glm(formula = choose_larger ~ 1, data = df, family = binomial()) # empty or intercept only model
  random_effect_sub <- glmer(formula = choose_larger ~ (1 | subject), data = df, family = binomial()) # only subject bird as random effect
  random_effect_pair <- glmer(formula = choose_larger ~ (1 | pair), data = df, family = binomial()) # only pair as random effect
  random_effect_sub_pair <- glmer(formula = choose_larger ~ (1 | subject) + (1 | pair), data = df, family = binomial) # subject bird and pair as random effect

  random_comparison <- compare_performance(random_effect_intercept, random_effect_sub, random_effect_pair, random_effect_sub_pair)
  bf_values_random <- bayesfactor_models(random_effect_intercept, random_effect_sub, random_effect_pair, random_effect_sub_pair, denominator = random_effect_intercept)
  random_comparison_table <- random_comparison |>
    mutate(BF = as.numeric(bf_values_random))
  best_random_effect_model <- eval(parse(text = random_comparison_table$Name[which(random_comparison_table$BF == max(random_comparison_table$BF))]))
  if(inherits(best_random_effect_model, what = "glm")) {
    best_random_effect <- sub("choose_larger ~ ", "", best_random_effect_model$formula)
  } else if (inherits(best_random_effect_model, what = "glmerMod")) {
    best_random_effect <- paste0(" + ", sub("choose_larger ~ ", "", best_random_effect_model@call[2]))
    # best_random_effect <- sub(", data = df, family = binomial())", "", best_random_effect)
  }


  ## Fixed effects ----------------------

  if(inherits(best_random_effect_model, what = "glm")) {
    fixed_difference_model <- glm(formula = choose_larger ~ difference, data = df, family = binomial) # difference as the IV
    fixed_ratio_model <- glm(formula = choose_larger ~ ratio, data = df, family = binomial) # ratio as the IV
    fixed_no_interaction_model <- glm(formula = choose_larger ~ difference + ratio, data = df, family = binomial) # no interaction term with main effects
    full_fixed_model <- glm(formula = choose_larger ~ difference * ratio, data = df, family = binomial) # full model
  } else if (inherits(best_random_effect_model, what = "glmerMod")) {
    fixed_difference_model <- glmer(formula = as.formula(paste0("choose_larger ~ difference", best_random_effect)), data = df, family = binomial) # difference as the IV
    fixed_ratio_model <- glmer(formula = as.formula(paste0("choose_larger ~ ratio", best_random_effect)), data = df, family = binomial) # ratio as the IV
    fixed_no_interaction_model <- glmer(formula = as.formula(paste0("choose_larger ~ difference + ratio", best_random_effect)), data = df, family = binomial) # no interaction term with main effects
    full_fixed_model <- glmer(formula = as.formula(paste0("choose_larger ~ difference * ratio", best_random_effect)), data = df, family = binomial) # full model
  }

  # Likelihood ratio tests for model comparison
  fixed_model_comparison <- compare_performance(random_effect_intercept, fixed_ratio_model, fixed_difference_model, fixed_no_interaction_model, full_fixed_model)

  fixed_bayes_comparison <- bayesfactor_models(random_effect_intercept, fixed_ratio_model, fixed_difference_model, fixed_no_interaction_model, full_fixed_model, denominator = random_effect_intercept)

  fixed_comparison_table <- fixed_model_comparison |>
    mutate(BF = as.numeric(fixed_bayes_comparison))

  # Determine the model of best fit
  bestfit <- eval(parse(text = fixed_comparison_table$Name[which(fixed_comparison_table$BIC == min(fixed_comparison_table$BIC))]))


  ## Plots -----------------------------------

  # Plot effects of difference on choice
  diff_bird_graph <- ggplot(data = choice_means_subject_diff, aes(x = difference, y = percent_larger)) +
    geom_line(aes(group = subject, color = subject), alpha = 0.5) +
    labs(y = "Percent larger chosen", x = "Difference") +
    geom_point(data = choice_means_diff_means, size = 3) +
    geom_errorbar(data = choice_means_diff_means, aes(x = difference, ymin = lower, ymax = upper), width = 0, linewidth = 1) +
    geom_hline(yintercept = 50, linetype = "dashed") +
    scale_y_continuous(breaks = seq(0, 100, 10), limits = c(0, 100)) +
    theme_bw(base_size = 22, base_family = "Arial") +
    theme(
      legend.position = "none",
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank()
    )

  # Plot effects of ratio on choice
  ratio_bird_graph <- ggplot(data = choice_means_subject_ratio, aes(x = ratio, y = percent_larger)) +
    labs(y = "Percent larger chosen", x = "Ratio") +
    geom_line(aes(group = subject, color = subject), alpha = 0.5) +
    geom_point(data = choice_means_ratio_means, size = 3) +
    geom_errorbar(data = choice_means_ratio_means, aes(x = ratio, ymin = lower, ymax = upper), width = 0, linewidth = 1) +
    geom_hline(yintercept = 50, linetype = "dashed") +
    scale_x_continuous(breaks = c(0.17, 0.2, 0.25, 0.33, 0.4, 0.5, 0.6, 0.67, 0.75, 0.8, 0.83)) +
    scale_y_continuous(breaks = seq(0, 100, 10), limits = c(0, 100)) +
    theme_bw(base_size = 22, base_family = "Arial") +
    theme(
      legend.position = "none",
      axis.text.x = element_text(angle = 60, hjust = 1),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank()
    )

  ## Tables -----------------------------------

  # Create tables of BF values
  random_models <- c("1", "(1|subject)", "(1|pair)", "(1|subject) + (1|pair)")
  fixed_models <- c("intercept only", "ratio", "difference", "difference + ratio", "difference * ratio")

  random_bf_df <- tibble(
    Model = random_models,
    AIC = random_comparison_table$AIC,
    BIC = random_comparison_table$BIC,
    BF = random_comparison_table$BF
  )

  fixed_bf_df <- tibble(
    Model = fixed_models,
    AIC = fixed_comparison_table$AIC,
    BIC = fixed_comparison_table$BIC,
    BF = fixed_comparison_table$BF
  )

  # random_bf_table <- (random_bf_df)
  # fixed_bf_table <- (fixed_bf_df)

  # Create Output to use for manuscript
  output <- list(ttest = large_pref_ttest, ttestbf = large_pref_ttest_bf, ttest_norm = ttest_normality, CI_difference = choice_means_subject_diff, CI_ratio = choice_means_ratio_means, best_model_fit = bestfit, diff_fig = diff_bird_graph, ratio_fig = ratio_bird_graph, random_table = random_bf_df, fixed_table = fixed_bf_df)
}

# Count the number of interactions with each stooge
count_stooges <- function(stooge) {
  stoogerejected <- paste0(stooge, "_rejected")
  individual_preference_df <<- individual_preference_df |>
    mutate(!!stooge := ifelse(str_detect(chosenbirds, stooge), 1, 0),
           !!stoogerejected := ifelse(str_detect(rejectedbirds, stooge), 1, 0))
}


# Import data ------------------------------------------------------------------

all_data <- read_csv("wolff_etal_2023_data.csv", show_col_types = FALSE) |>
  mutate(ratio = small_num / large_num,
         diff = large_num - small_num,
         logistic = 1 / (1 + exp(large_num - small_num)),
         discrim = log(large_num / (large_num - small_num)),
         .after = large_num)

# Separate out data for each experiment
food1 <- all_data |>
  filter(study == "Food" & rep == 1) |>
  filter(!subject %in% c("Mulder", "Dartagnan"))

food2 <- all_data |>
  filter(study == "Food" & rep == 2) |>
  filter(!subject %in% c("Basil", "Robin"))

social1 <- all_data |>
  filter(study == "Social" & rep == 1) |>
  filter(!subject %in% c("Baloo")) |>
  filter(!small_num %in% 0)

social2 <- all_data |>
  filter(study == "Social" & rep == 2) |>
  filter(!subject %in% c()) |>
  filter(!small_num %in% 0)

combined_data <- bind_rows(food1, food2, social1, social2)

# Combine replicates
food_data <- bind_rows(food1, food2)
social_data <- bind_rows(social1, social2)


# Analyze data -----------------------------------------------------------------

## Reliability ---------------------
food_reliability <- cohen.kappa(cbind(food_data$choice, food_data$recode_choice))
social_reliability <- cohen.kappa(cbind(social_data$choice, social_data$recode_choice))

## Confirmatory analyses ---------------------
food1_results <- analyze_data(df = food1)
check_outliers(food1_results$best_model_fit)
boxTidwell(choose_larger ~ ratio, data = food1)

food2_results <- analyze_data(df = food2)
check_outliers(food2_results$best_model_fit)
boxTidwell(choose_larger ~ ratio, data = food2)

social1_results <- analyze_data(df = social1)
check_outliers(social1_results$best_model_fit)
boxTidwell(choose_larger ~ ratio, data = social1)

social2_results <- analyze_data(df = social2)
check_outliers(social2_results$best_model_fit)
boxTidwell(choose_larger ~ ratio, data = social2)

## Exploratory analyses requested by reviewers --------------------------

# Run analyses on combined data
food_all_results <- analyze_data(df = food_data)
check_outliers(food_all_results$best_model_fit)
boxTidwell(choose_larger ~ ratio, data = food_data)

social_all_results <- analyze_data(df = social_data)
check_outliers(social_all_results$best_model_fit)
boxTidwell(choose_larger ~ ratio, data = social_data)

# Sex comparison
food_subjects <- food_data |>
  summarise(prop_choice = mean(choose_larger, na.rm = TRUE), .by = c(subject, sex, rep))
food_sex_norm <- shapiro.test(food_subjects$prop_choice)
food_sex_equal <- leveneTest(prop_choice ~ sex, data = food_subjects)
food_sex_ttest <- t.test(formula = prop_choice ~ sex, data = food_subjects)
food_sex_ttest_bf <- ttestBF(formula = prop_choice ~ sex, data = food_subjects)

social_subjects <- social_data |>
  summarise(prop_choice = mean(choose_larger, na.rm = TRUE), .by = c(subject, sex, rep))
social_sex_norm <- shapiro.test(social_subjects$prop_choice)
social_sex_equal <- leveneTest(prop_choice ~ sex, data = social_subjects)
social_sex_ttest <- t.test(formula = prop_choice ~ sex, data = social_subjects)
social_sex_ttest_bf <- ttestBF(formula = prop_choice ~ sex, data = social_subjects)

# Co-linearity of ratio and difference
food_model <- glm(formula = choose_larger ~ diff * ratio, data = food_data, family = binomial)
vif(food_model)
social_model <- glm(formula = choose_larger ~ diff * ratio, data = social_data, family = binomial)
vif(social_model)

food_data_ratio0.5 <- food_data |>
  filter(ratio == 1/2)
food_ratio0.5_intercept <- glm(formula = choose_larger ~ 1, data = food_data_ratio0.5, family = binomial)
food_ratio0.5_full <- glm(formula = choose_larger ~ diff, data = food_data_ratio0.5, family = binomial)

food_ratio0.5_bf <- bayesfactor_models(food_ratio0.5_intercept, food_ratio0.5_full, denominator = food_ratio0.5_intercept)

social_data_ratio0.5 <- social_data |>
  filter(ratio == 1/2)
social_ratio0.5_intercept <- glm(formula = choose_larger ~ 1, data = social_data_ratio0.5, family = binomial)
social_ratio0.5_full <- glm(formula = choose_larger ~ diff, data = social_data_ratio0.5, family = binomial)

social_ratio0.5_bf <- bayesfactor_models(social_ratio0.5_intercept, social_ratio0.5_full, denominator = social_ratio0.5_intercept)


# Build plots ------------------------------------------------------------------

# Food
food_figures <- food1_results$diff_fig + food1_results$ratio_fig +
  food2_results$diff_fig + food2_results$ratio_fig +
  plot_annotation(tag_levels = "a", tag_prefix = "(", tag_suffix = ")")
ggsave("figures/food_figure.png", width = 14, height = 10)

# Social
social_figures <- social1_results$diff_fig + social1_results$ratio_fig +
  social2_results$diff_fig + social2_results$ratio_fig +
  plot_annotation(tag_levels = "a", tag_prefix = "(", tag_suffix = ")")
ggsave("figures/social_figure.png", width = 14, height = 10)


# Supplementary materials ---------------------------------------

## Calculate mean trials per session ---------------------

sessions_avg_food1 <- food1 %>%
  count(subject, session)

sessions_avg_food2 <- food2 %>%
  count(subject, session)

session_mean <- mean(c(sessions_avg_food1$n, sessions_avg_food2$n))

sessions_social1 <- social1 |>
  count(subject)

sessions_social2 <- social2 |>
  count(subject)

sessions_social1 <- social1
sum(str_count(social1$small_birds, "Fox")) + sum(str_count(social1$large_birds, "Fox"))


## Demographic table ------------------------

subject_ages<- c(12, 11, 15, 12, 12, 12, 14,10,12,10, 15,12,14,14,15,14,15,10,12,19,11)

subject_bird_info <- combined_data |>
  unite(unique_code, c(study, rep)) |>
  group_by(unique_code, sex, subject) |>
  summarise(n = n(), .groups = "drop") |>
  pivot_wider(names_from = unique_code, values_from = n, values_fill = 0) |>
  select(subject, everything()) |>
  mutate(across(contains("_"), ~ ifelse(.x == "0", "", "X"))) |>
  add_column(age = subject_ages) |>
  select(subject, sex, age, everything()) |>
  arrange(desc(Food_1), desc(Social_2))
subject_bird_info <- subject_bird_info[c(1:8, 10, 9, 11:21),]

stooge_birds <- combined_data |>
  filter(grepl("Social", study)) |>
  unite(stooges, small_birds, large_birds, sep = " ") |>
  mutate(stooges = str_replace_all(stooges, ",", "")) |>
  pull(stooges) |>
  str_split(" ") |>
  unlist() |>
  unique() |>
  sort()

stooge_ages_df <- tibble(stooge = c("Zappa", "Cash", "Pease", "Hagrid", "Bruno", "Mulder", "Mork", "Fox", "Comanche", "Sebastian", "Ariel", "Saffron", "Hermia", "Quince", "Scully", "Egeus", "Sapphire", "Chicklet", "Hippolyta"),
                         age  = c(11,11,14,11,19,11,12,11,10,19,19,12,14,14,11,14,12,12,14)) |>
  arrange(stooge)


stooge_bird_info <- tibble(stooge = stooge_birds,
                           sex = c("Male", "Male", "Male", "Male", "Male", "Female", "Male", "Male", "Female", "Female", "Male", "Male", "Male", "Female", "Female", "Female", "Female", "Male", "Male"),
                           age = stooge_ages_df$age,
                           social1_trials = map_dbl(stooge_birds, ~sum(str_count(social1$small_birds, .x)) + sum(str_count(social1$large_birds, .x))),
                           social2_trials = map_dbl(stooge_birds, ~sum(str_count(social2$small_birds, .x)) + sum(str_count(social2$large_birds, .x)))
) |>
  mutate(across(contains("social"), ~ na_if(.x, 0)))


## Table of factorial pairs ------------

factorial_pairs_df <- data.frame(
  Pair = c("1:2", "1:3", "1:4", "1:5", "1:6", "2:3", "2:4", "2:5", "2:6", "3:4", "3:5", "3:6", "4:5", "4:6", "5:6")) |>
  separate(Pair, into = c("small", "large"), remove = FALSE, convert = TRUE) |>
  mutate(Difference = large - small,
         Ratio = small / large,
         Social_2 = ifelse(small + large < 9, "X", "")) |>
  select(!small:large)
#   Difference = c("1", "2", "3", "4", "5", "1", "2", "3", "4", "1", "2", "3", "1", "2", "1"),
#   Ratio = c("0.50", "0.33", "0.25", "0.20", "0.17", "0.67", "0.50", "0.40", "0.33", "0.75", "0.60", "0.50", "0.80", "0.67", "0.83"),
#   Social_2 = c("X", "X", "X", "X", "X", "X", "X", "X", "X", "X", "X", "", "", "", "")
# )


## Random effect models ----------------

random_effect_df <- data.frame(
  Model = c("Intercept Only Model", "Subject Only Model", "Pair Only Model", "Both Subject and Pair"),
  Formula = c("choice ~ 1", "choice ~ (1|subject)", "choice ~ (1|pair)", "choice ~ (1|subject) + (1|pair)")
)


## Fixed effect models ---------------

fixed_effect_df <- data.frame(
  Model = c("Intercept Only Model", "Ratio Only Model", "Difference Only Model", "Both Fixed Effects, No Interaction", "Both Fixed Effects, With Interaction"),
  Formula = c("choice ~ 1", "choice ~ ratio", "choice ~ difference", "choice ~ ratio + difference", "choice ~ ratio * difference")
)


## Bird preference table --------------------------

# Create column of birds that were chosen and create columns showing how often each bird was chosen and not chosen

individual_preference_df <- combined_data |>
  filter(study == "Social") |>
  mutate(chosenbirds = ifelse(choose_larger == "1", large_birds, small_birds),
         rejectedbirds = ifelse(choose_larger == "0", large_birds, small_birds))

map(stooge_bird_info$stooge, count_stooges)

# Create table of values for replicate 1

individual_preference_table <- individual_preference_df |>
  group_by(rep, sex) |>
  summarise(across(Ariel:Zappa_rejected, ~ sum(.x, na.rm = TRUE)), .groups = "drop") |>
  pivot_longer(-c(rep:sex), names_to = "stooge", values_to = "presence") |>
  mutate(
    chosen = ifelse(grepl(x = stooge, pattern = "_rejected"), "rejected", "chosen"),
    stooge = str_replace(stooge, "_rejected", "")
  ) |>
  unite(sex_chosen, c("sex", "chosen")) |>
  pivot_wider(id_cols = rep:stooge, names_from = sex_chosen, values_from = presence) |>
  mutate(
    total_trials = Female_chosen + Male_chosen + Female_rejected + Male_rejected,
    female_percent = Female_chosen / (Female_chosen + Female_rejected) * 100,
    male_percent = Male_chosen / (Male_chosen + Male_rejected) * 100,
    overall_percent = (Female_chosen + Male_chosen) / (Female_chosen + Male_chosen + Female_rejected + Male_rejected) * 100
  ) |>
  arrange(rep, overall_percent) |>
  filter(overall_percent != 0) |>
  left_join(select(stooge_bird_info, stooge:age), by = "stooge") |>
  relocate(sex:age, .after = stooge) |>
  arrange(rep, desc(sex), overall_percent)

# Create heatmap for individual preference data

## Replicate 1

heatmap_df_1 <- individual_preference_df |>
  filter(rep == "1") |>
  group_by(subject) |>
  summarise(across(Ariel:Zappa_rejected, ~ sum(.x, na.rm = TRUE)), .groups = "drop") |>
  pivot_longer(-subject, names_to = "stooge", values_to = "presence") |>
  mutate(
    chosen = ifelse(grepl(x = stooge, pattern = "_rejected"), "rejected", "chosen"),
    stooge = str_replace(stooge, "_rejected", "")
  ) |>
  unite(subject_chosen, c("subject", "chosen")) |>
  pivot_wider(stooge, names_from = subject_chosen, values_from = presence) |>
  rename(Black_Elk_chosen = "Black Elk_chosen",
         Black_Elk_rejected = "Black Elk_rejected") |>
  mutate(
    Basil = Basil_chosen / (Basil_chosen + Basil_rejected) *100,
    Black_Elk = Black_Elk_chosen / (Black_Elk_chosen + Black_Elk_rejected) *100,
    Chicklet = Chicklet_chosen / (Chicklet_chosen + Chicklet_rejected) *100,
    Dill = Dill_chosen / (Dill_chosen + Dill_rejected) *100,
    Flute = Flute_chosen / (Flute_chosen + Flute_rejected) *100,
    Hippolyta = Hippolyta_chosen / (Hippolyta_chosen + Hippolyta_rejected) *100,
    Juan = Juan_chosen / (Juan_chosen + Juan_rejected) *100,
    Juniper = Juniper_chosen / (Juniper_chosen + Juniper_rejected) *100,
    Robin = Robin_chosen / (Robin_chosen + Robin_rejected) *100,
    Rooster = Rooster_chosen / (Rooster_chosen + Rooster_rejected) *100) |>
  select(stooge, Basil:Rooster)|>
  na.omit()

heatmap_df_long_1 <- heatmap_df_1 |>
  pivot_longer(-stooge, names_to = "subject", values_to = "percent") |>
  mutate(replicate = 1, .before = 1)

## Replicate 2

heatmap_df_2 <- individual_preference_df |>
  filter(individual_preference_df$rep == "2") |>
  group_by(subject) |>
  summarise(across(Ariel:Zappa_rejected, ~ sum(.x, na.rm = TRUE)), .groups = "drop") |>
  pivot_longer(-subject, names_to = "stooge", values_to = "presence") |>
  mutate(
    chosen = ifelse(grepl(x = stooge, pattern = "_rejected"), "rejected", "chosen"),
    stooge = str_replace(stooge, "_rejected", "")
  ) |>
  unite(subject_chosen, c("subject", "chosen")) |>
  pivot_wider(stooge, names_from = subject_chosen, values_from = presence) |>
  rename(Heman_chosen = "He-man_chosen",
         Heman_rejected = "He-man_rejected") |>
  mutate(
    Dartagnan = Dartagnan_chosen / (Dartagnan_chosen + Dartagnan_rejected) *100,
    Dumbledore = Dumbledore_chosen / (Dumbledore_chosen + Dumbledore_rejected) *100,
    Fern = Fern_chosen / (Fern_chosen + Fern_rejected) *100,
    Fozzie = Fozzie_chosen / (Fozzie_chosen + Fozzie_rejected) *100,
    Heman = Heman_chosen / (Heman_chosen + Heman_rejected) *100,
    Mork = Mork_chosen / (Mork_chosen + Mork_rejected) *100,
    Mote = Mote_chosen / (Mote_chosen + Mote_rejected) *100,
    Mulder = Mulder_chosen / (Mulder_chosen + Mulder_rejected) *100,
    Prudence = Prudence_chosen / (Prudence_chosen + Prudence_rejected) *100,
    Uno = Uno_chosen / (Uno_chosen + Uno_rejected) *100)|>
  select(stooge, Dartagnan:Uno)|>
  na.omit()

heatmap_df_long_2 <- heatmap_df_2 |>
  pivot_longer(-stooge, names_to = "subject", values_to = "percent") |>
  mutate(replicate = 2, .before = 1)

# Combine data

heatmap_df_long <- bind_rows(heatmap_df_long_1, heatmap_df_long_2) |>
  left_join(stooge_bird_info, by = "stooge") |>
  select(replicate, stooge, stooge_sex = sex, subject, percent) |>
  left_join(subject_bird_info, by = "subject") |>
  select(replicate:subject, subject_sex = sex, percent) |>
  mutate(subject_sex = ifelse(subject == "Black_Elk", "Male", subject_sex),
         subject_sex = ifelse(subject == "Heman", "Male", subject_sex))

# Plot heatmaps for both replicates

heatmap_visual <- heatmap_df_long |>
  mutate(stooge = ifelse(stooge %in% pull(filter(stooge_bird_info, sex == "Female"), stooge), paste0(stooge, "*"), stooge),
         subject = ifelse(subject %in% pull(filter(subject_bird_info, sex == "Female"), subject), paste0(subject, "*"), subject),
         stooge = fct_relevel(stooge, "Egeus*", "Hermia*", "Hippolyta*", "Quince*", "Saffron*", "Sapphire*", "Scully*"),
         subject =  fct_relevel(subject, "Flute*", "Juniper*", "Hippolyta*", "Robin*", "Uno*"),
         subject = fct_recode(subject, "Black Elk" = "Black_Elk"),
         hline = ifelse(replicate == 1, 6.5, 4.5),
         vline = ifelse(replicate == 1, 4.5, 1.5),
         replicate = paste("Replicate", replicate)) |>
  ggplot(aes(x = subject, y = stooge, fill = percent)) +
  geom_tile() +
  facet_wrap(~replicate, scales = "free") +
  geom_hline(aes(yintercept = hline)) +
  geom_vline(aes(xintercept = vline)) +
  scale_fill_gradient2(high = "#005AB5",
                       low = "#139272",
                       midpoint = 50) +
  labs(y = "Conspecific Birds", x = "Subject Birds", fill = "Percent\nchoice") +
  theme_bw()+
  theme(axis.text.x = element_text(angle = 70, hjust = 1),
        text = element_text(size = 16, family = "Arial"))

ggsave("figures/individual_preference.png", width = 8, height = 5)


## Sex differences in preference ---------------------------------------------------------

male_subject_data <- heatmap_df_long |>
  filter(subject_sex == "Male")
female_subject_data <- heatmap_df_long |>
  filter(subject_sex == "Female")
summary(lmer(percent ~ stooge_sex + (1 | subject) + (1 | stooge), data = male_subject_data))
summary(lmer(percent ~ stooge_sex + (1 | subject) + (1 | stooge), data = female_subject_data))
male_subject_data |>
  group_by(stooge_sex) |>
  summarise(mean(percent))
male_subject_wide <- male_subject_data |>
  group_by(subject, stooge_sex) |>
  summarise(mean_percent = mean(percent)) |>
  pivot_wider(id_cols = subject, names_from = stooge_sex, values_from = mean_percent)
male_pref_ttest <- t.test(male_subject_wide$Male, male_subject_wide$Female, paired = TRUE)
male_pref_ttestbf <- ttestBF(male_subject_wide$Male, male_subject_wide$Female, paired = TRUE)
female_subject_data |>
  group_by(stooge_sex) |>
  summarise(mean(percent))
female_subject_wide <- female_subject_data |>
  group_by(subject, stooge_sex) |>
  summarise(mean_percent = mean(percent)) |>
  pivot_wider(id_cols = subject, names_from = stooge_sex, values_from = mean_percent)
female_pref_ttest <- t.test(female_subject_wide$Male, female_subject_wide$Female, paired = TRUE)
female_pref_ttestbf <- ttestBF(female_subject_wide$Male, female_subject_wide$Female, paired = TRUE)
