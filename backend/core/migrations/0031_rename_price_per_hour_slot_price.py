from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0030_platformtransaction'),
    ]

    operations = [
        migrations.RenameField(
            model_name='venue',
            old_name='price_per_hour',
            new_name='slot_price',
        ),
    ]
